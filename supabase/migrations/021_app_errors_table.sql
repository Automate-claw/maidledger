-- App errors logging table for debugging
CREATE TABLE IF NOT EXISTS app_errors (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  error_type TEXT NOT NULL,
  source TEXT NOT NULL,  -- 'scan' | 'chat' | 'price_history_insert' | etc
  message TEXT,
  extra_data JSONB,
  resolved BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE app_errors ENABLE ROW LEVEL SECURITY;

-- Allow authenticated users to insert errors (for logging)
CREATE POLICY "allow_authenticated_insert_app_errors"
  ON app_errors FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

-- Allow authenticated users to view their own errors
CREATE POLICY "allow_authenticated_select_app_errors"
  ON app_errors FOR SELECT
  USING (auth.role() = 'authenticated');