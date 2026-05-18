-- Migration: 013b_product_aliases_language_origin
-- Add language_origin field to product_aliases for multi-language support

ALTER TABLE public.product_aliases ADD COLUMN IF NOT EXISTS language_origin TEXT CHECK (language_origin IN ('zh','en','tl','id','my','other'));