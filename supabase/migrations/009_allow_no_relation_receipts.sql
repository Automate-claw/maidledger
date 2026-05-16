-- Migration: Allow receipts without employer relation
-- Helper can record expense even before linking to employer
-- employer_id is nullable; when relation is created, receipts are backfilled

-- 1. Drop NOT NULL constraint on employer_id
ALTER TABLE receipts
  ALTER COLUMN employer_id DROP NOT NULL;

-- 2. Allow helper_id to be nullable too (for future flexibility)
ALTER TABLE receipts
  ALTER COLUMN helper_id DROP NOT NULL;

-- 3. Function to backfill receipts when helper links to employer
CREATE OR REPLACE FUNCTION backfill_receipts_on_link()
RETURNS TRIGGER AS $$
BEGIN
  -- When a relation becomes active, update all unassigned receipts
  IF NEW.status = 'active' AND TG_OP = 'UPDATE' THEN
    UPDATE receipts
    SET employer_id = NEW.employer_id,
        relation_id = NEW.id
    WHERE helper_id = NEW.helper_id
      AND employer_id IS NULL
      AND relation_id IS NULL;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Trigger to fire backfill on relation status change
DROP TRIGGER IF EXISTS on_relation_activated ON employer_helper_relations;
CREATE TRIGGER on_relation_activated
  AFTER UPDATE OF status ON employer_helper_relations
  FOR EACH ROW EXECUTE FUNCTION backfill_receipts_on_link();