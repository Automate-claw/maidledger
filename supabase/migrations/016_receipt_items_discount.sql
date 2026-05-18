-- Migration: 016_receipt_items_discount
-- Adds discount/bundle detection columns to receipt_items and price_history

ALTER TABLE public.receipt_items ADD COLUMN IF NOT EXISTS actual_price DECIMAL(10,2);
ALTER TABLE public.receipt_items ADD COLUMN IF NOT EXISTS is_discounted BOOLEAN DEFAULT false;
ALTER TABLE public.receipt_items ADD COLUMN IF NOT EXISTS discount_note TEXT;

ALTER TABLE public.price_history ADD COLUMN IF NOT EXISTS original_price DECIMAL(10,2);
ALTER TABLE public.price_history ADD COLUMN IF NOT EXISTS total_paid DECIMAL(10,2);
ALTER TABLE public.price_history ADD COLUMN IF NOT EXISTS is_discount_bundle BOOLEAN DEFAULT false;