-- Migration 040: User price alert configuration
-- Allows employers to customize alert thresholds per category or globally
-- Defaults are set in price-alert-engine; this table overrides per-user

CREATE TABLE IF NOT EXISTS price_alert_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employer_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  config_key TEXT NOT NULL,          -- 'global' | 'vegetables' | 'meat' | 'seafood' | etc.
  config_value JSONB NOT NULL DEFAULT '{}',
  -- Default config_value structure:
  -- { "enabled": true, "yellow_threshold": 0.12, "red_threshold": 0.35, "silent_below": 0.05 }
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(employer_id, config_key)
);

CREATE INDEX IF NOT EXISTS idx_price_alert_config_employer
  ON price_alert_config(employer_id);

COMMENT ON TABLE price_alert_config IS
  'Per-user alert threshold overrides. Null means use system defaults.';
