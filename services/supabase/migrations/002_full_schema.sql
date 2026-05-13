-- ===========================================
-- MaidLedger Database Schema for Supabase
-- Run this in Supabase SQL Editor
-- ===========================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ===========================================
-- USER PROFILES
-- ===========================================
CREATE TABLE user_profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('employer', 'helper')),
  name TEXT NOT NULL,
  phone TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;

-- Profiles viewable by same user
CREATE POLICY "Users can view own profile"
  ON user_profiles FOR SELECT
  USING (auth.uid() = id);

-- Users can update own profile
CREATE POLICY "Users can update own profile"
  ON user_profiles FOR UPDATE
  USING (auth.uid() = id);

-- ===========================================
-- EMPLOYER-HELPER RELATIONSHIPS
-- ===========================================
CREATE TABLE employer_helper_relations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  employer_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  helper_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'pending')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(employer_id, helper_id)
);

ALTER TABLE employer_helper_relations ENABLE ROW LEVEL SECURITY;

-- Employers can view their helpers
CREATE POLICY "Employers can view their helpers"
  ON employer_helper_relations FOR SELECT
  USING (auth.uid() = employer_id);

-- Employers can manage their relations
CREATE POLICY "Employers can manage their relations"
  ON employer_helper_relations FOR ALL
  USING (auth.uid() = employer_id);

-- Helpers can view their employers
CREATE POLICY "Helpers can view their employers"
  ON employer_helper_relations FOR SELECT
  USING (auth.uid() = helper_id);

-- ===========================================
-- RECEIPTS
-- ===========================================
CREATE TABLE receipts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  employer_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  helper_id UUID REFERENCES user_profiles(id),
  relation_id UUID REFERENCES employer_helper_relations(id),

  -- Receipt data
  raw_text TEXT NOT NULL,
  parsed_data JSONB,
  amount DECIMAL(10,2),
  category TEXT,
  items JSONB DEFAULT '[]'::jsonb,

  -- Sync metadata (offline-first)
  sync_status TEXT DEFAULT 'pending' CHECK (sync_status IN ('pending', 'synced', 'conflict')),
  local_timestamp BIGINT NOT NULL,
  server_timestamp BIGINT,

  -- Image stored locally, not uploaded
  image_local_path TEXT,

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE receipts ENABLE ROW LEVEL SECURITY;

-- Employers can view receipts from their helpers
CREATE POLICY "Employers can view receipts"
  ON receipts FOR SELECT
  USING (
    auth.uid() = employer_id
    OR auth.uid() = helper_id
  );

-- Helpers can insert receipts
CREATE POLICY "Helpers can insert receipts"
  ON receipts FOR INSERT
  WITH CHECK (auth.uid() = helper_id);

-- Helpers can update their pending receipts
CREATE POLICY "Helpers can update own receipts"
  ON receipts FOR UPDATE
  USING (auth.uid() = helper_id);

-- ===========================================
-- PRICE DATA (from scraper)
-- ===========================================
CREATE TABLE price_data (
  id SERIAL PRIMARY KEY,
  supermarket TEXT NOT NULL CHECK (supermarket IN ('hktvmall', 'wellcome', 'parknshop')),
  category TEXT NOT NULL CHECK (category IN ('fish', 'pork', 'beef', 'chicken', 'vegetables', 'others')),
  product_name TEXT NOT NULL,
  price DECIMAL(10,2) NOT NULL,
  unit TEXT DEFAULT 'unit',
  source_url TEXT,
  scraped_at TIMESTAMPTZ DEFAULT NOW(),

  -- Unique constraint: one price per product per supermarket per day
  UNIQUE(supermarket, category, product_name, DATE(scraped_at))
);

ALTER TABLE price_data ENABLE ROW LEVEL SECURITY;

-- Anyone can read price data
CREATE POLICY "Anyone can read price data"
  ON price_data FOR SELECT
  USING (true);

-- Only service role can insert/update price data (scraper)
CREATE POLICY "Service can manage price data"
  ON price_data FOR ALL
  USING (auth.jwt()->>'role' = 'service_role');

-- ===========================================
-- PRICE ALERTS
-- ===========================================
CREATE TABLE price_alerts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  receipt_id UUID REFERENCES receipts(id) ON DELETE CASCADE,
  category TEXT NOT NULL,
  input_price DECIMAL(10,2) NOT NULL,
  avg_price DECIMAL(10,2),
  min_price DECIMAL(10,2),
  max_price DECIMAL(10,2),
  difference_percent DECIMAL(5,1),
  alert_level TEXT CHECK (alert_level IN ('green', 'yellow', 'red', 'unknown')),
  message TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE price_alerts ENABLE ROW LEVEL SECURITY;

-- Users can view their alerts
CREATE POLICY "Users can view their alerts"
  ON price_alerts FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM receipts
      WHERE receipts.id = price_alerts.receipt_id
      AND (receipts.employer_id = auth.uid() OR receipts.helper_id = auth.uid())
    )
  );

-- ===========================================
-- EXPENSE SUMMARY (for dashboard)
-- ===========================================
CREATE TABLE expense_summaries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  employer_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  helper_id UUID REFERENCES user_profiles(id),
  relation_id UUID REFERENCES employer_helper_relations(id),

  -- Monthly summary
  month DATE NOT NULL,  -- First day of month
  category TEXT,
  total_amount DECIMAL(10,2) DEFAULT 0,
  transaction_count INTEGER DEFAULT 0,

  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(employer_id, helper_id, month, category)
);

ALTER TABLE expense_summaries ENABLE ROW LEVEL SECURITY;

-- Employers can view their summaries
CREATE POLICY "Employers can view summaries"
  ON expense_summaries FOR SELECT
  USING (auth.uid() = employer_id);

-- ===========================================
-- FUNCTIONS
-- ===========================================

-- Function to get price alert
CREATE OR REPLACE FUNCTION get_price_alert(
  p_category TEXT,
  p_price DECIMAL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_avg_price DECIMAL;
  v_min_price DECIMAL;
  v_max_price DECIMAL;
  v_difference DECIMAL;
  v_alert_level TEXT;
  v_message TEXT;
BEGIN
  -- Get average price for category from last 7 days
  SELECT AVG(price), MIN(price), MAX(price)
  INTO v_avg_price, v_min_price, v_max_price
  FROM price_data
  WHERE category = p_category
    AND scraped_at > NOW() - INTERVAL '7 days';

  -- Calculate difference
  IF v_avg_price IS NOT NULL AND v_avg_price > 0 THEN
    v_difference := ((p_price - v_avg_price) / v_avg_price) * 100;

    -- Determine alert level
    IF v_difference < -10 THEN
      v_alert_level := 'green';
      v_message := '✅ 比超市平好多！';
    ELSIF v_difference < 5 THEN
      v_alert_level := 'green';
      v_message := '✅ 正常價';
    ELSIF v_difference < 20 THEN
      v_alert_level := 'yellow';
      v_message := '⚠️ 偏貴';
    ELSE
      v_alert_level := 'red';
      v_message := '🚨 貴過超市好多！';
    END IF;
  ELSE
    v_difference := 0;
    v_alert_level := 'unknown';
    v_message := '⚪ 暂无超市價格數據';
  END IF;

  RETURN jsonb_build_object(
    'category', p_category,
    'input_price', p_price,
    'avg_price', ROUND(v_avg_price::numeric, 2),
    'min_price', v_min_price,
    'max_price', v_max_price,
    'difference_percent', ROUND(v_difference::numeric, 1),
    'alert_level', v_alert_level,
    'message', v_message
  );
END;
$$;

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for updated_at
CREATE TRIGGER update_user_profiles_updated_at
  BEFORE UPDATE ON user_profiles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_receipts_updated_at
  BEFORE UPDATE ON receipts
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_expense_summaries_updated_at
  BEFORE UPDATE ON expense_summaries
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ===========================================
-- INITIAL STRUCTURE SUMMARY
-- ===========================================
-- Tables: user_profiles, employer_helper_relations, receipts,
--         price_data, price_alerts, expense_summaries
--
-- Key Design Decisions:
-- 1. Offline-first: sync_status + local_timestamp on receipts
-- 2. Image NOT stored in Supabase (stored locally, only text synced)
-- 3. Price data is public read (scraper writes, all can read)
-- 4. Row Level Security enabled on all tables