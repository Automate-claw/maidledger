-- Migration 034: District Price Index
-- Regional cost-of-living adjustment coefficients for cross-district price comparisons
-- E.g. 中西區係數 1.2 (more expensive), 元朗區係數 0.85 (cheaper)
--
-- Usage: when comparing prices across districts,
--   adjusted_price = raw_price / district_index
--   So a $10 item in 中西区 (index=1.2) becomes $8.33 in 元朗 baseline

CREATE TABLE IF NOT EXISTS district_price_index (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  district TEXT NOT NULL,              -- '中西區' | '灣仔' | '將軍澳' | '元朗' | etc.
  region TEXT NOT NULL,                -- '港島' | '九龍' | '新界'
  category TEXT NOT NULL,              -- '超市' | '街市' | 'all'
  index_coefficient DECIMAL(4, 3) NOT NULL DEFAULT 1.0,
  recorded_month DATE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(district, category, recorded_month)
);

CREATE INDEX IF NOT EXISTS idx_district_region
  ON district_price_index(region, recorded_month DESC);
CREATE INDEX IF NOT EXISTS idx_district_name
  ON district_price_index(district, recorded_month DESC);

COMMENT ON TABLE district_price_index IS
  '地區物價修正系數。用法：cross_district_price = raw_price / index_coefficient';
