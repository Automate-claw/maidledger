-- Migration: fix trigger to only fire on parse_status='pending'
-- Prevents chat-orchestrate receipts (parse_status='parsed') from re-triggering receipt-vision

DROP TRIGGER IF EXISTS on_receipt_inserted ON public.receipts;
DROP FUNCTION IF EXISTS public.handle_new_receipt();

CREATE OR REPLACE FUNCTION public.handle_new_receipt()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only fire for INSERTs with parse_status = 'pending'
  -- Chat flow (createFromChat) uses parse_status = 'parsed', so it won't trigger
  IF NEW.parse_status = 'pending' THEN
    PERFORM net.http_post(
      url := 'https://hnyazfrkzpxdjiyfzemm.supabase.co/functions/v1/receipt-orchestrate',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
      ),
      body := jsonb_build_object(
        'receipt_id', NEW.id
      )
    );
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_receipt_inserted
  AFTER INSERT ON public.receipts
  FOR EACH ROW
  WHEN (NEW.parse_status = 'pending')
  EXECUTE FUNCTION public.handle_new_receipt();

COMMENT ON FUNCTION public.handle_new_receipt() IS
  'Fires on INSERT to receipts WHERE parse_status=pending, calls receipt-orchestrate via pg_net webhook';
