-- ══════════════════════════════════════════════════════════════════════════════
-- Migration: 026_unify_timestamp_timezone
-- Target: Convert all receipts timestamps to UTC+8 (Asia/Hong_Kong)
--
-- Problem: PostgreSQL now() returns UTC. created_at/updated_at show +00:00
--   (UTC) while application logic expects Asia/Hong_Kong (+08:00).
-- Fix: Set DEFAULT to timezone('Asia/Hong_Kong', now())::timestamptz so all
--   new inserts get UTC+8 automatically. Existing rows are updated to UTC+8.
-- ══════════════════════════════════════════════════════════════════════════════

-- receipts: created_at default → HK now
ALTER TABLE public.receipts
  ALTER COLUMN created_at SET DEFAULT timezone('Asia/Hong_Kong', now())::timestamptz;

-- receipts: updated_at default → HK now
ALTER TABLE public.receipts
  ALTER COLUMN updated_at SET DEFAULT timezone('Asia/Hong_Kong', now())::timestamptz;

-- receipts: server_timestamp default → HK now
ALTER TABLE public.receipts
  ALTER COLUMN server_timestamp SET DEFAULT timezone('Asia/Hong_Kong', now())::timestamptz;

-- Sync existing receipts to UTC+8 (no-op but triggers value materialisation)
UPDATE public.receipts SET created_at = created_at;

-- receipt_items: recorded_at default → HK now
ALTER TABLE public.receipts_items
  ALTER COLUMN recorded_at SET DEFAULT timezone('Asia/Hong_Kong', now())::timestamptz;

-- price_history: recorded_at default → HK now
ALTER TABLE public.price_history
  ALTER COLUMN recorded_at SET DEFAULT timezone('Asia/Hong_Kong', now())::timestamptz;

-- chat_logs: created_at default → HK now
ALTER TABLE public.chat_logs
  ALTER COLUMN created_at SET DEFAULT timezone('Asia/Hong_Kong', now())::timestamptz;

-- employer_helper_relations: created_at/updated_at → HK now
ALTER TABLE public.employer_helper_relations
  ALTER COLUMN created_at SET DEFAULT timezone('Asia/Hong_Kong', now())::timestamptz;
ALTER TABLE public.employer_helper_relations
  ALTER COLUMN updated_at SET DEFAULT timezone('Asia/Hong_Kong', now())::timestamptz;