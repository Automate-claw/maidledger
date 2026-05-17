-- Migration: 012_master_products_and_aliases
-- Phase 1 MVP: ILIKE-based product matching (no pgvector dependency)

-- 1. master_products: canonical product definitions
CREATE TABLE IF NOT EXISTS public.master_products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  canonical_name TEXT NOT NULL,
  brand TEXT,
  prd_cate TEXT,
  default_unit TEXT,
  search_keywords TEXT[],
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. product_aliases: all raw names encountered (OCR, crawler, manual)
CREATE TABLE IF NOT EXISTS public.product_aliases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  raw_name TEXT UNIQUE NOT NULL,
  master_product_id UUID REFERENCES master_products(id) ON DELETE CASCADE,
  source TEXT CHECK (source IN ('ocr', 'crawler', 'manual', 'seed')),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. Link receipt_items to master_products
ALTER TABLE public.receipt_items
  ADD COLUMN IF NOT EXISTS master_product_id UUID REFERENCES master_products(id) ON DELETE SET NULL;

-- Indexes for ILIKE performance
CREATE INDEX IF NOT EXISTS idx_master_products_keywords ON master_products USING GIN(search_keywords);
CREATE INDEX IF NOT EXISTS idx_master_products_cate ON master_products(prd_cate);
CREATE INDEX IF NOT EXISTS idx_product_aliases_master ON product_aliases(master_product_id);

-- RLS
ALTER TABLE public.master_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_aliases ENABLE ROW LEVEL SECURITY;

-- Everyone can read master_products (needed for matching)
CREATE POLICY "Anyone can read master_products" ON master_products FOR SELECT USING (true);

-- Service role can write master_products
CREATE POLICY "Service role can manage master_products" ON master_products
  FOR ALL USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');

-- Everyone can read aliases
CREATE POLICY "Anyone can read aliases" ON product_aliases FOR SELECT USING (true);

-- Service role can write aliases
CREATE POLICY "Service role can manage aliases" ON product_aliases
  FOR ALL USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');

-- receipt_items master_product_id: anyone can update their own (via app)
CREATE POLICY "Users can update own receipt_items master_product_id" ON receipt_items
  FOR UPDATE USING (auth.uid() = (SELECT helper_id FROM receipts WHERE id = receipt_id))
  WITH CHECK (auth.uid() = (SELECT helper_id FROM receipts WHERE id = receipt_id));