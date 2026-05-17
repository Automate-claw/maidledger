-- Migration: 011_fix_receipt_items_insert
-- Fix RLS: Allow unlinked helpers to insert receipt items
-- When helper links to employer, backfill_receipts_on_link trigger will
-- populate employer_id/relation_id, so the existing SELECT policy will
-- automatically grant employer access to these records after linking.

-- Drop the overly strict receipt_items insert policy
-- (required relation_id AND active link, which blocks unlinked helpers)
DROP POLICY IF EXISTS "Helpers can insert receipt items" ON receipt_items;

-- New policy: helper can insert items for ANY receipt where they are the helper
-- (works for both linked AND unlinked receipts)
-- After linking: backfill trigger sets employer_id/relation_id on existing receipts
-- → employer's existing SELECT policy (matching on employer_id) will grant access
CREATE POLICY "Helpers can insert receipt items for own receipts"
  ON receipt_items FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM receipts
      WHERE receipts.id = receipt_id
      AND receipts.helper_id = auth.uid()
    )
  );