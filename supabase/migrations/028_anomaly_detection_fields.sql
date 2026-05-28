-- 028_anomaly_detection_fields: Phase 1 of 4
-- - adds transaction_date to receipts (business date, user-facing)
-- - adds date_anomaly flag (LLM-detected date inconsistency)
-- - adds created_by audit trail to receipts and employer_payments

-- =============================================
-- receipts: add transaction_date, date_anomaly, created_by
-- =============================================
ALTER TABLE receipts
  ADD COLUMN IF NOT EXISTS transaction_date DATE,
  ADD COLUMN IF NOT EXISTS date_anomaly BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES user_profiles(id);

-- Backfill transaction_date from created_at for existing records (conservative default)
UPDATE receipts
SET transaction_date = created_at::date
WHERE transaction_date IS NULL;

-- RLS: allow insert with created_by, allow update of date_anomaly by owner
ALTER TABLE receipts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Helpers can insert receipts" ON receipts;
CREATE POLICY "Helpers can insert receipts with created_by" ON receipts
  FOR INSERT WITH CHECK (auth.uid() = helper_id);

DROP POLICY IF EXISTS "Helpers can update their pending receipts" ON receipts;
CREATE POLICY "Helpers can update own receipts" ON receipts
  FOR UPDATE USING (auth.uid() = helper_id OR auth.uid() = employer_id);

-- =============================================
-- employer_payments: add created_by
-- =============================================
ALTER TABLE employer_payments
  ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES user_profiles(id);

-- Backfill created_by = helper_id for existing records
UPDATE employer_payments
SET created_by = helper_id
WHERE created_by IS NULL;

ALTER TABLE employer_payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Helpers can insert own payments" ON employer_payments;
CREATE POLICY "Helpers can insert own payments with created_by" ON employer_payments
  FOR INSERT WITH CHECK (auth.uid() = helper_id);

DROP POLICY IF EXISTS "Both can view payments" ON employer_payments;
CREATE POLICY "Both can view payments" ON employer_payments
  FOR SELECT USING (auth.uid() = helper_id OR auth.uid() = employer_id);

DROP POLICY IF EXISTS "Both can update own payments" ON employer_payments;
CREATE POLICY "Both can update own payments" ON employer_payments
  FOR UPDATE USING (auth.uid() = helper_id OR auth.uid() = employer_id);

-- =============================================
-- Indexes
-- =============================================
CREATE INDEX IF NOT EXISTS idx_receipts_transaction_date ON receipts(transaction_date);
CREATE INDEX IF NOT EXISTS idx_receipts_date_anomaly ON receipts(date_anomaly);
CREATE INDEX IF NOT EXISTS idx_receipts_created_by ON receipts(created_by);
CREATE INDEX IF NOT EXISTS idx_ep_created_by ON employer_payments(created_by);