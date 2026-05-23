-- 026_employer_payments: 僱主俾錢記錄
CREATE TABLE IF NOT EXISTS employer_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  relation_id UUID NOT NULL REFERENCES employer_helper_relations(id) ON DELETE CASCADE,
  employer_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  helper_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  amount DECIMAL(10,2) NOT NULL,
  payment_date DATE NOT NULL DEFAULT CURRENT_DATE,
  note TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE employer_payments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Helpers can insert own payments" ON employer_payments FOR INSERT WITH CHECK (auth.uid() = helper_id);
CREATE POLICY "Both can view payments" ON employer_payments FOR SELECT USING (auth.uid() = helper_id OR auth.uid() = employer_id);
CREATE POLICY "Both can update own payments" ON employer_payments FOR UPDATE USING (auth.uid() = helper_id OR auth.uid() = employer_id);
CREATE POLICY "Both can delete own payments" ON employer_payments FOR DELETE USING (auth.uid() = helper_id OR auth.uid() = employer_id);
CREATE INDEX idx_ep_relation_id ON employer_payments(relation_id);
CREATE INDEX idx_ep_payment_date ON employer_payments(payment_date);
