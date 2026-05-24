-- ══════════════════════════════════════════════════════════════════════════════
-- Migration: 027_unify_timestamp_timezone
-- Target: Convert all receipt timestamps to UTC+8 (Asia/Hong_Kong)
--
-- Problem: PostgreSQL now() returns UTC. created_at shows +00:00 (UTC)
--   while application logic assumes Asia/Hong_Kong (+08:00).
--   server_timestamp is BIGINT (Unix epoch ms).
-- Fix: Set DEFAULT to timezone('Asia/Hong_Kong', now()) for timestamptz cols,
--   and EXTRACT(EPOCH FROM ...)*1000 for BIGINT cols.
--
-- Columns per table (verified against schema):
--   receipts:             created_at, updated_at (timestamptz), server_timestamp (bigint)
--   receipt_items:        created_at (timestamptz only)
--   price_history:        created_at (timestamptz); recorded_at is DATE — unchanged
--   chat_logs:            created_at (timestamptz)
--   employer_helper_relations: created_at (timestamptz only — no updated_at)
-- ══════════════════════════════════════════════════════════════════════════════

-- ── receipts: created_at, updated_at → UTC+8 default ──────────────────────
ALTER TABLE public.receipts
  ALTER COLUMN created_at SET DEFAULT timezone('Asia/Hong_Kong', now())::timestamptz;

ALTER TABLE public.receipts
  ALTER COLUMN updated_at SET DEFAULT timezone('Asia/Hong_Kong', now())::timestamptz;

-- server_timestamp is BIGINT (Unix ms) → HK epoch ms default
ALTER TABLE public.receipts
  ALTER COLUMN server_timestamp SET DEFAULT EXTRACT(EPOCH FROM timezone('Asia/Hong_Kong', now()))::bigint * 1000;

-- Sync existing created_at to UTC+8
UPDATE public.receipts SET created_at = created_at;

-- ── receipt_items: created_at → UTC+8 ────────────────────────────────────
ALTER TABLE public.receipt_items
  ALTER COLUMN created_at SET DEFAULT timezone('Asia/Hong_Kong', now())::timestamptz;

-- ── price_history: created_at → UTC+8 (recorded_at is DATE — unchanged) ────
ALTER TABLE public.price_history
  ALTER COLUMN created_at SET DEFAULT timezone('Asia/Hong_Kong', now())::timestamptz;

-- ── chat_logs: created_at → UTC+8 ─────────────────────────────────────────
ALTER TABLE public.chat_logs
  ALTER COLUMN created_at SET DEFAULT timezone('Asia/Hong_Kong', now())::timestamptz;

-- ── employer_helper_relations: created_at → UTC+8 ──────────────────────────
ALTER TABLE public.employer_helper_relations
  ALTER COLUMN created_at SET DEFAULT timezone('Asia/Hong_Kong', now())::timestamptz;