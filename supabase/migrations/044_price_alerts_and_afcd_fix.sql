-- Migration 044: Fix pending failures from 032 and 033
-- 032 failed: price_alerts table didn't exist (only price_alert_config)
-- 033 failed: now() is not IMMUTABLE in index predicate

BEGIN;

-- ── 032 fix: create price_alerts table ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.price_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  prd_cate TEXT,
  shop_id UUID REFERENCES shops(id) ON DELETE SET NULL,
  alert_type TEXT NOT NULL CHECK (alert_type IN ('price_drop', 'below_anchor', 'anomaly')),
  threshold_pct DECIMAL(6, 2),
  last_triggered_at TIMESTAMPTZ,
  last_triggered_price DECIMAL(10, 2),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  is_enabled BOOLEAN DEFAULT true
);

ALTER TABLE public.price_alerts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own price_alerts" ON public.price_alerts
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_price_alerts_user ON price_alerts(user_id);
CREATE INDEX IF NOT EXISTS idx_price_alerts_enabled ON price_alerts(is_enabled) WHERE is_enabled = true;

-- Apply 032 columns
ALTER TABLE price_alerts
  ADD COLUMN IF NOT EXISTS d_pct DECIMAL(6, 2),
  ADD COLUMN IF NOT EXISTS is_fresh_food BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS message TEXT;

CREATE INDEX IF NOT EXISTS idx_price_alerts_d_pct ON price_alerts(d_pct) WHERE d_pct IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_price_alerts_fresh_food ON price_alerts(is_fresh_food) WHERE is_fresh_food = true;

-- ── 033 fix: afcd_wholesale_prices with IMMUTABLE date ─────────────────────
CREATE TABLE IF NOT EXISTS public.afcd_wholesale_prices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category TEXT NOT NULL CHECK (category IN ('蔬菜', '淡水魚', '海水魚')),
  item_name TEXT NOT NULL,
  wholesale_price DECIMAL(10, 2) NOT NULL,
  unit TEXT NOT NULL CHECK (unit IN ('斤', '両', '公斤')),
  retail_multiplier DECIMAL(4, 2) DEFAULT 2.0,
  recorded_date DATE NOT NULL,
  source_url TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(category, item_name, recorded_date)
);

CREATE INDEX IF NOT EXISTS idx_afcd_category ON afcd_wholesale_prices(category, recorded_date DESC);

-- Use CURRENT_DATE instead of now() in predicate (CURRENT_DATE is STABLE, not IMMUTABLE)
-- But for index predicate safety, use a constant expression
CREATE INDEX IF NOT EXISTS idx_afcd_item_name ON afcd_wholesale_prices(item_name);

COMMENT ON TABLE afcd_wholesale_prices IS
  'AFCD 每日批發價：長沙灣蔬菜批發市場、長沙灣淡水魚批發市場報價';

COMMIT;
