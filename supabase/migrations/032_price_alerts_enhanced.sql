-- Migration 032: Enhance price_alerts for Stage 1 (Buffer Zone + humanized messages)
-- Adds: d_pct, is_fresh_food, message

ALTER TABLE price_alerts
  ADD COLUMN IF NOT EXISTS d_pct DECIMAL(6, 2),
  ADD COLUMN IF NOT EXISTS is_fresh_food BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS message TEXT;

CREATE INDEX IF NOT EXISTS idx_price_alerts_d_pct
  ON price_alerts(d_pct)
  WHERE d_pct IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_price_alerts_fresh_food
  ON price_alerts(is_fresh_food)
  WHERE is_fresh_food = true;
