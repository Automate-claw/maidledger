-- Migration: update trigger to call new receipt-orchestrate function
-- Previously pointed to receipt-processor, now points to receipt-orchestrate

create or replace function public.handle_new_receipt()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform net.http_post(
    url := 'https://hnyazfrkzpxdjiyfzemm.supabase.co/functions/v1/receipt-orchestrate',
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

comment on function public.handle_new_receipt() is
  'Fires on INSERT to receipts, calls receipt-orchestrate edge function via pg_net webhook';