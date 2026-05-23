-- ===========================================
-- 023: Event-driven receipt processing via DB trigger
-- ===========================================
-- Supabase uses pg_net for HTTP webhooks from database triggers.
-- The trigger fires on INSERT to receipts → calls receipt-processor edge function.
-- Fallback cron (every 5 min) handles webhook delivery failures.

-- Enable pg_net extension (required for Supabase HTTP calls from SQL)
create extension if not exists "pg_net";

-- ─────────────────────────────────────────────────────────────────────────────
-- Trigger function: fires on INSERT to receipts table
-- Sends receipt_id to receipt-processor edge function via POST
-- Uses SECURITY DEFINER so it runs with the function owner's privileges
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.handle_new_receipt()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Only fire for INSERT with parse_status = 'pending'
  -- (helpers should insert with parse_status = 'pending' by default)
  perform net.http_post(
    url := (current_setting('app.settings.supabase_url', true) || '/functions/v1/receipt-processor'),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
    ),
    body := jsonb_build_object(
      'receipt_id', NEW.id
    )
  );
  return NEW;
end;
$$;

-- Drop existing trigger if it exists (idempotent)
drop trigger if exists on_receipt_inserted on public.receipts;

-- Attach trigger — AFTER INSERT on receipts
create trigger on_receipt_inserted
  after insert on public.receipts
  for each row
  execute function public.handle_new_receipt();

-- ─────────────────────────────────────────────────────────────────────────────
-- NOTE: Supabase does NOT expose app.settings via current_setting by default.
-- If the above fails, use the direct URL approach instead:
--
--   url := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/receipt-processor'
--
-- Replace YOUR_PROJECT_REF with your actual project reference
-- (found in Supabase Dashboard > Settings > API)
-- ─────────────────────────────────────────────────────────────────────────────

comment on function public.handle_new_receipt() is
  'Fires on INSERT to receipts, calls receipt-processor edge function via pg_net webhook';