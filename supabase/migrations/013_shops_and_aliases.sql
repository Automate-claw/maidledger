-- Migration: 013_shops_and_aliases
-- Standardized shop/location entities for crowdsourced price system

-- shops: standardized shop/location entities
CREATE TABLE IF NOT EXISTS public.shops (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  canonical_name TEXT NOT NULL,
  shop_type TEXT CHECK (shop_type IN ('supermarket','wet_market','pharmacy','convenience','online','restaurant','cafe','takeaway','other')),
  region TEXT,
  district TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- shop_aliases: all raw names encountered
CREATE TABLE IF NOT EXISTS public.shop_aliases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  raw_name TEXT UNIQUE NOT NULL,
  shop_id UUID REFERENCES shops(id) ON DELETE CASCADE,
  source TEXT CHECK (source IN ('ocr','crawler','manual','seed')),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Add shop_id to receipts
ALTER TABLE public.receipts ADD COLUMN IF NOT EXISTS shop_id UUID REFERENCES shops(id) ON DELETE SET NULL;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_shops_type ON shops(shop_type);
CREATE INDEX IF NOT EXISTS idx_shops_region ON shops(region);
CREATE INDEX IF NOT EXISTS idx_shop_aliases_shop ON shop_aliases(shop_id);

-- RLS
ALTER TABLE public.shops ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shop_aliases ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read shops" ON shops FOR SELECT USING (true);
CREATE POLICY "Service role can manage shops" ON shops FOR ALL USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');

CREATE POLICY "Anyone can read aliases" ON shop_aliases FOR SELECT USING (true);
CREATE POLICY "Service role can manage aliases" ON shop_aliases FOR ALL USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');

CREATE POLICY "Users can update own receipts shop_id" ON receipts FOR UPDATE USING (auth.uid() = (SELECT helper_id FROM receipts WHERE id = receipts.id)) WITH CHECK (auth.uid() = (SELECT helper_id FROM receipts WHERE id = receipts.id));