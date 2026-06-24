-- Migration 033: AFCD Wholesale Prices Table
-- Source: Hong Kong Agriculture, Fisheries and Conservation Department (AFCD)
-- Daily wholesale prices for vegetables, fresh water fish, marine fish
-- Website: https://www.afcd.gov.hk

CREATE TABLE IF NOT EXISTS afcd_wholesale_prices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category TEXT NOT NULL,          -- '蔬菜' | '淡水魚' | '海水魚'
  item_name TEXT NOT NULL,         -- e.g. '菜心', '西蘭花', '黃鱔'
  wholesale_price DECIMAL(10, 2) NOT NULL,
  unit TEXT NOT NULL,              -- '斤' | '両' | '公斤'
  retail_multiplier DECIMAL(4, 2) DEFAULT 2.0,  -- 批發價 × 倍數 = 零售估算
  recorded_date DATE NOT NULL,
  source_url TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(category, item_name, recorded_date)
);

CREATE INDEX IF NOT EXISTS idx_afcd_category
  ON afcd_wholesale_prices(category, recorded_date DESC);
CREATE INDEX IF NOT EXISTS idx_afcd_item
  ON afcd_wholesale_prices(item_name gin_trgm_ops)
  WHERE recorded_date > now() - interval '7 days';

COMMENT ON TABLE afcd_wholesale_prices IS
  'AFCD 每日批發價：長沙灣蔬菜批發市場、長沙灣淡水魚批發市場報價';
