-- ============================================
-- Phase 1 Task 1.1: Create cc_prices table
-- Date: 2026-05-27
-- Purpose: Store Consumer Council price data as canonical reference
-- ============================================

-- Create cc_prices table
CREATE TABLE IF NOT EXISTS cc_prices (
    cc_code TEXT PRIMARY KEY,                    -- P000003343
    name_en TEXT,
    name_zh TEXT,
    brand_en TEXT,
    brand_zh TEXT,
    cat1_en TEXT,
    cat1_zh TEXT,
    cat2_en TEXT,
    cat2_zh TEXT,
    cat3_en TEXT,
    cat3_zh TEXT,
    prices JSONB,                               -- { "WELLCOME": 54.90, "PARKNSHOP": 71.90 }
    standard_weight_g INTEGER,                   -- e.g., 170 for "170g" package
    price_per_100g DECIMAL,                      -- normalized price for comparison
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for fast lookup
CREATE INDEX IF NOT EXISTS idx_cc_prices_name_zh ON cc_prices(name_zh);
CREATE INDEX IF NOT EXISTS idx_cc_prices_name_en ON cc_prices(name_en);
CREATE INDEX IF NOT EXISTS idx_cc_prices_cat2 ON cc_prices(cat2_en);
CREATE INDEX IF NOT EXISTS idx_cc_prices_standard_weight ON cc_prices(standard_weight_g);

-- ============================================
-- Phase 1 Task 1.3: Update receipt_items (not expense_records)
-- Note: MaidLedger uses receipt_items for expense line items
-- ============================================

ALTER TABLE receipt_items
    ADD COLUMN IF NOT EXISTS weight_grams DECIMAL;

ALTER TABLE receipt_items
    ADD COLUMN IF NOT EXISTS price_per_gram DECIMAL;

ALTER TABLE receipt_items
    ADD COLUMN IF NOT EXISTS cc_code TEXT REFERENCES cc_prices(cc_code);

ALTER TABLE receipt_items
    ADD COLUMN IF NOT EXISTS cc_price_per_gram DECIMAL;

-- ============================================
-- Phase 1 Task 1.4: Update user_profiles for household size
-- ============================================

ALTER TABLE user_profiles
    ADD COLUMN IF NOT EXISTS household_size INTEGER;

-- ============================================
-- Verification queries (run these to confirm)
-- ============================================

-- Check cc_prices table
-- SELECT * FROM cc_prices LIMIT 5;

-- Check new columns in receipt_items
-- SELECT column_name, data_type FROM information_schema.columns 
-- WHERE table_name = 'receipt_items' AND column_name IN ('weight_grams', 'price_per_gram', 'cc_code', 'cc_price_per_gram');

-- Check household_size column
-- SELECT column_name, data_type FROM information_schema.columns 
-- WHERE table_name = 'user_profiles' AND column_name = 'household_size';

COMMENT ON TABLE cc_prices IS 'Consumer Council price data - supermarket reference prices';
COMMENT ON COLUMN cc_prices.cc_code IS 'Consumer Council product code, e.g. P000003343';
COMMENT ON COLUMN cc_prices.standard_weight_g IS 'Standard package weight in grams, extracted from product name';
COMMENT ON COLUMN cc_prices.price_per_100g IS 'Normalized price per 100g for cross-product comparison';