-- Migration: Enable Realtime for receipts table
-- This enables Supabase Realtime CDC on receipts table

-- Add receipts to the supabase_realtime publication
-- (This was done via API, adding migration for documentation)

-- Note: Realtime is enabled when:
-- 1. REPLICA IDENTITY is set on the table (for UPDATE/DELETE)
-- 2. Table is in a publication (supabase_realtime)
-- 3. RLS is enabled (already done in previous migrations)

-- Set REPLICA IDENTITY for proper realtime update/delete events
ALTER TABLE receipts REPLICA IDENTITY DEFAULT;
ALTER TABLE receipt_items REPLICA IDENTITY DEFAULT;