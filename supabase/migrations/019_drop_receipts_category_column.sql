-- Migration: 019_drop_receipts_category_column
-- Migrate data from category → store_cate, then drop redundant category column
-- chat-parser already returns store_cate; Flutter was incorrectly using category

-- Move any existing category data to store_cate (only where store_cate is null)
UPDATE receipts SET store_cate = category
WHERE store_cate IS NULL AND category IS NOT NULL;

-- Drop the orphan category column (now redundant with store_cate)
ALTER TABLE receipts DROP COLUMN IF EXISTS category;