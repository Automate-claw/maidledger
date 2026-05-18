-- Migration: 015_price_alerts_enhanced
-- Enhanced price alerts with weather suppression

CREATE TABLE IF NOT EXISTS public.weather_signals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  signal_type TEXT NOT NULL,
  signal_name TEXT,
  issued_at TIMESTAMPTZ NOT NULL,
  expired_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.price_alert_suppression (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  start_time TIMESTAMPTZ NOT NULL,
  end_time TIMESTAMPTZ NOT NULL,
  reason TEXT,
  suppressed_categories TEXT[],
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.price_alerts ADD COLUMN IF NOT EXISTS comparison_type TEXT DEFAULT 'last_purchase';
ALTER TABLE public.price_alerts ADD COLUMN IF NOT EXISTS price_before DECIMAL(10,2);
ALTER TABLE public.price_alerts ADD COLUMN IF NOT EXISTS weather_suppressed BOOLEAN DEFAULT false;
ALTER TABLE public.price_alerts ADD COLUMN IF NOT EXISTS region TEXT;

ALTER TABLE public.weather_signals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.price_alert_suppression ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read weather_signals" ON weather_signals FOR SELECT USING (true);
CREATE POLICY "Service role can manage weather_signals" ON weather_signals FOR ALL USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');

CREATE POLICY "Anyone can read price_alert_suppression" ON price_alert_suppression FOR SELECT USING (true);
CREATE POLICY "Service role can manage price_alert_suppression" ON price_alert_suppression FOR ALL USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');