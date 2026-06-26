-- Migration: 043_product_aliases_brand
-- Add brand column to product_aliases for brand-aware matching

ALTER TABLE public.product_aliases
  ADD COLUMN IF NOT EXISTS brand TEXT;

CREATE INDEX IF NOT EXISTS idx_product_aliases_brand ON product_aliases(brand)
  WHERE brand IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_product_aliases_raw_brand ON product_aliases(raw_name, brand);

-- Backfill: extract brand from existing raw_name patterns (common supermarket prefixes)
-- This is informational only; the main fix is in product-manager matching logic
UPDATE product_aliases pa
  SET brand = sub.extracted_brand
  FROM (
    SELECT DISTINCT ON (ri.item_name)
      ri.item_name,
      ri.extracted_brand
    FROM receipt_items ri
    WHERE ri.extracted_brand IS NOT NULL
    ORDER BY ri.item_name, ri.id DESC
  ) sub
  WHERE pa.brand IS NULL
    AND pa.raw_name = sub.item_name;
