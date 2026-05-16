-- ===========================================
-- Migration 003: Receipt Items Normalization + Short Code
-- Adds: store_name, store_cate, location, transaction_date, image_local_path
-- Adds: short_code to user_profiles for simple 6-char employer codes
-- Creates: receipt_items table (1:N from receipts)
-- ===========================================

-- 1. Add new columns to receipts
ALTER TABLE receipts
  ADD COLUMN IF NOT EXISTS store_name TEXT,
  ADD COLUMN IF NOT EXISTS store_cate TEXT CHECK (store_cate IN ('supermarket', 'wet_market', 'pharmacy', 'convenience', 'online', 'other')),
  ADD COLUMN IF NOT EXISTS location TEXT,
  ADD COLUMN IF NOT EXISTS transaction_date DATE,
  ADD COLUMN IF NOT EXISTS image_local_path TEXT;

-- 2. Create receipt_items table
CREATE TABLE IF NOT EXISTS receipt_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  receipt_id UUID NOT NULL REFERENCES receipts(id) ON DELETE CASCADE,

  -- Item data (denormalized raw for traceability)
  item_name TEXT NOT NULL,
  item_raw_text TEXT,          -- Original OCR line text
  qty DECIMAL(10,3) DEFAULT 1,
  unit_price DECIMAL(10,2),
  prd_cate TEXT CHECK (prd_cate IN ('fish', 'pork', 'beef', 'chicken', 'vegetables', 'rice', 'oil', 'seasoning', 'snack', 'drink', 'daily', 'other')),

  -- Line total (may differ from unit_price * qty due to discounts)
  line_total DECIMAL(10,2),

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_receipt_items_receipt_id ON receipt_items(receipt_id);
CREATE INDEX IF NOT EXISTS idx_receipt_items_category ON receipt_items(prd_cate);

-- Enable RLS
ALTER TABLE receipt_items ENABLE ROW LEVEL SECURITY;

-- Employers and helpers can view receipt items (matching receipts policy)
CREATE POLICY "Users can view receipt items"
  ON receipt_items FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM receipts
      WHERE receipts.id = receipt_id
      AND (receipts.employer_id = auth.uid() OR receipts.helper_id = auth.uid())
    )
  );

-- Helpers can insert receipt items (matching receipts policy)
CREATE POLICY "Helpers can insert receipt items"
  ON receipt_items FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM receipts
      WHERE receipts.id = receipt_id
      AND receipts.helper_id = auth.uid()
      AND receipts.relation_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM employer_helper_relations
        WHERE employer_helper_relations.id = receipts.relation_id
        AND employer_helper_relations.helper_id = auth.uid()
        AND employer_helper_relations.employer_id = receipts.employer_id
        AND employer_helper_relations.status = 'active'
      )
    )
  );

-- Helpers can update their own receipt items
CREATE POLICY "Helpers can update receipt items"
  ON receipt_items FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM receipts
      WHERE receipts.id = receipt_id
      AND receipts.helper_id = auth.uid()
    )
  );

-- Helpers can delete their own receipt items
CREATE POLICY "Helpers can delete receipt items"
  ON receipt_items FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM receipts
      WHERE receipts.id = receipt_id
      AND receipts.helper_id = auth.uid()
    )
  );

-- 3. Function to link helper to employer via invite code
-- Adds helper_id to existing pending relation or creates one
CREATE OR REPLACE FUNCTION link_helper_to_employer_via_code(
  p_employer_code UUID,
  p_helper_id UUID
)
RETURNS employer_helper_relations
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_relation employer_helper_relations%ROWTYPE;
BEGIN
  -- Look for a pending relation with this employer, update to active
  UPDATE employer_helper_relations
  SET status = 'active', helper_id = p_helper_id
  WHERE employer_id = p_employer_code
    AND status = 'pending'
    AND helper_id IS NULL
  RETURNING * INTO v_relation;

  IF v_relation.id IS NULL THEN
    -- No pending relation found, create new active one
    INSERT INTO employer_helper_relations (employer_id, helper_id, status)
    VALUES (p_employer_code, p_helper_id, 'active')
    RETURNING * INTO v_relation;
  END IF;

  RETURN v_relation;
END;
$$;

-- 4. Add helper link function (accepts employer user ID as code)
CREATE OR REPLACE FUNCTION get_employer_by_code(p_code TEXT)
RETURNS user_profiles
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN (
    SELECT up FROM user_profiles up
    WHERE up.id = p_code::UUID
    AND up.role = 'employer'
  );
END;
$$;