-- Migration: 014_price_history
-- Price history write flow for crowdsourced price system

CREATE TABLE IF NOT EXISTS public.price_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  master_product_id UUID REFERENCES master_products(id) ON DELETE CASCADE,
  shop_id UUID REFERENCES shops(id) ON DELETE SET NULL,
  location TEXT,
  region TEXT,
  price DECIMAL(10,2) NOT NULL,
  unit TEXT,
  source_receipt_id UUID REFERENCES receipts(id) ON DELETE SET NULL,
  recorded_at DATE DEFAULT CURRENT_DATE,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_price_history_product_date ON price_history(master_product_id, recorded_at);
CREATE INDEX IF NOT EXISTS idx_price_history_region ON price_history(region, recorded_at);
CREATE INDEX IF NOT EXISTS idx_price_history_shop ON price_history(shop_id, recorded_at);

ALTER TABLE public.price_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read price_history" ON price_history FOR SELECT USING (true);
CREATE POLICY "Service role can insert price_history" ON price_history FOR INSERT WITH CHECK (auth.role() = 'service_role' OR auth.uid() IS NOT NULL);