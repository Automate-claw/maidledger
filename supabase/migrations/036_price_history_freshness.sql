-- Migration 036: Add freshness_weight to price_history
-- Used for time-decay weighting in trimmed mean calculations
-- Formula:
--   days_ago = 0 → weight = 1.0
--   days_ago = 1 → weight = 0.7
--   days_ago = 2 → weight = 0.3
--   days_ago >= 3 → weight = 0.1

ALTER TABLE price_history
  ADD COLUMN IF NOT EXISTS freshness_weight DECIMAL(3, 2) DEFAULT 1.0,
  ADD COLUMN IF NOT EXISTS days_ago INT;  -- cached calculation for convenience

-- Populate freshness_weight based on recorded_at for existing records
UPDATE price_history
  SET
    days_ago = GREATEST(0, DATE_PART('day', NOW() - recorded_at::timestamptz))::INT,
    freshness_weight = CASE
      WHEN DATE_PART('day', NOW() - recorded_at::timestamptz) = 0 THEN 1.0
      WHEN DATE_PART('day', NOW() - recorded_at::timestamptz) = 1 THEN 0.7
      WHEN DATE_PART('day', NOW() - recorded_at::timestamptz) = 2 THEN 0.3
      ELSE 0.1
    END
  WHERE freshness_weight IS NULL OR freshness_weight = 1.0;

CREATE INDEX IF NOT EXISTS idx_price_history_freshness
  ON price_history(master_product_id, recorded_at DESC)
  WHERE freshness_weight >= 0.1;
