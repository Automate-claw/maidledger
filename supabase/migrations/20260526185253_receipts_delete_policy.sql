-- ===========================================
-- Migration 028: Add receipts delete policy + improve delete error handling
-- ===========================================

-- Helpers can delete their own receipts
CREATE POLICY "Helpers can delete own receipts"
  ON receipts FOR DELETE
  USING (
    auth.uid() = helper_id
  );
