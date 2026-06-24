-- Migration 041: Product Standard Names mapping
-- Caches LLM-output standard_name → master_product_id mappings
-- This avoids re-calling LLM or re-matching for known products
-- Populated by product-manager during upsert flow

CREATE TABLE IF NOT EXISTS product_standard_names (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  standard_name TEXT NOT NULL UNIQUE,
  master_product_id UUID NOT NULL REFERENCES master_products(id) ON DELETE CASCADE,
  language TEXT NOT NULL DEFAULT 'zh-Hant',
  is_fresh_food BOOLEAN DEFAULT false,
  confidence_score DECIMAL(3, 2) DEFAULT 0.5,
  match_count INT DEFAULT 1,         -- how many times this mapping was used
  last_used_at TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_product_standard_names_master
  ON product_standard_names(master_product_id);
CREATE INDEX IF NOT EXISTS idx_product_standard_names_fresh
  ON product_standard_names(is_fresh_food)
  WHERE is_fresh_food = true;

COMMENT ON TABLE product_standard_names IS
  'LLM standard_name → master_product_id lookup cache. Populated during product-manager upsert.';
