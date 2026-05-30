-- ============================================================
-- Migration: 030_cleanup_obsolete
-- Date: 2026-05-30
-- Purpose: Remove obsolete/empty tables and cleanup unused columns
-- Backup: docs/db_backup_20260530.sql
-- ============================================================

-- ─── PHASE 2: DROP empty/obsolete tables ───

-- price_alerts: 0 rows, never used (replaced by cc_prices comparison)
DROP TABLE IF EXISTS price_alerts CASCADE;

-- price_data: 0 rows, scraper output (cc_prices already has this data)
DROP TABLE IF EXISTS price_data CASCADE;

-- weather_signals: 0 rows, weather-based suppression not implemented
DROP TABLE IF EXISTS weather_signals CASCADE;

-- price_alert_suppression: 0 rows, never used
DROP TABLE IF EXISTS price_alert_suppression CASCADE;

-- app_errors: 0 rows, logging done elsewhere (cloudflare/supabase logs)
DROP TABLE IF EXISTS app_errors CASCADE;

-- expense_summaries: 0 rows, monthly category aggregation (flutter bug: never written)
-- NOTE: chat_screen._upsertExpenseSummary() writes to this but receipts come from chat flow
-- which bypasses this path. If needed later, re-implement properly.
DROP TABLE IF EXISTS expense_summaries CASCADE;

-- ─── PHASE 3: DROP unused columns ───

-- receipt_items.item_raw_text: 55/55 rows NULL (100% empty, never written)
ALTER TABLE receipt_items DROP COLUMN IF EXISTS item_raw_text;

-- ─── PHASE 4: Add unit tracking columns to price_history ───
-- Fix: user selects 500g but writes as "件" — no standardization
-- Solution: track actual weight + standardized unit display + per-unit price

ALTER TABLE price_history ADD COLUMN IF NOT EXISTS weight_g INTEGER;
ALTER TABLE price_history ADD COLUMN IF NOT EXISTS unit_display TEXT;
ALTER TABLE price_history ADD COLUMN IF NOT EXISTS unit_type TEXT CHECK (unit_type IN ('g', 'kg', 'pcs', 'ml', 'unknown'));
ALTER TABLE price_history ADD COLUMN IF NOT EXISTS price_per_kg NUMERIC;
ALTER TABLE price_history ADD COLUMN IF NOT EXISTS price_per_pcs NUMERIC;

COMMENT ON COLUMN price_history.weight_g IS 'Actual weight in grams (500 = 500g, 0 = unit count)';
COMMENT ON COLUMN price_history.unit_display IS 'Display label: 500g, 6粒, 1L';
COMMENT ON COLUMN price_history.unit_type IS 'Unit category: g=weight, kg=weight, pcs=count, ml=volume';
COMMENT ON COLUMN price_history.price_per_kg IS 'Normalized price per kg (for weight items)';
COMMENT ON COLUMN price_history.price_per_pcs IS 'Normalized price per piece (for count items)';

-- ─── PHASE 5: Add unit tracking columns to receipt_items ───

ALTER TABLE receipt_items ADD COLUMN IF NOT EXISTS unit_display TEXT;
ALTER TABLE receipt_items ADD COLUMN IF NOT EXISTS unit_type TEXT CHECK (unit_type IN ('g', 'kg', 'pcs', 'ml', 'unknown'));

COMMENT ON COLUMN receipt_items.unit_display IS 'Display label for UI: 500g, 6粒';
COMMENT ON COLUMN receipt_items.unit_type IS 'Unit category: g=weight, kg=weight, pcs=count, ml=volume';

-- ─── Done ───