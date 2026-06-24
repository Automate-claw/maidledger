-- Migration 031: Add LLM-normalized fields to receipt_items
-- Stage 1: normalized_unit_price infrastructure

ALTER TABLE receipt_items
  ADD COLUMN IF NOT EXISTS normalized_unit_price DECIMAL(12, 4),
  ADD COLUMN IF NOT EXISTS standard_name TEXT,
  ADD COLUMN IF NOT EXISTS is_fresh_food BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS confidence_score DECIMAL(3, 2) DEFAULT 0.5;

-- Index for fast standard_name lookups (cross-household queries)
CREATE INDEX IF NOT EXISTS idx_receipt_items_standard_name
  ON receipt_items(standard_name)
  WHERE standard_name IS NOT NULL;

-- Index for freshness food filter
CREATE INDEX IF NOT EXISTS idx_receipt_items_fresh_food
  ON receipt_items(is_fresh_food)
  WHERE is_fresh_food = true;

COMMENT ON COLUMN receipt_items.normalized_unit_price IS
  'Standardized unit price (per 100g / per piece / per liang). All price comparisons use this field.';
COMMENT ON COLUMN receipt_items.standard_name IS
  'LLM-output canonical product name for cross-household matching (e.g. 牛肉片, 菜心).';
COMMENT ON COLUMN receipt_items.is_fresh_food IS
  'True for wet market items: vegetables, meat, fish, tofu. Has wider buffer zones in alerts.';
COMMENT ON COLUMN receipt_items.confidence_score IS
  'LLM parsing confidence: 0.0-1.0. Low confidence items are excluded from crowdsourced averages.';
