-- Migration 039: RPC function update_receipt_shop
-- Updates receipt.shop_id from matched shop_manager result

CREATE OR REPLACE FUNCTION update_receipt_shop(
  p_receipt_id UUID,
  p_shop_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE receipts
  SET shop_id = p_shop_id, updated_at = now()
  WHERE id = p_receipt_id;
END;
$$;

GRANT EXECUTE ON FUNCTION update_receipt_shop TO authenticated;
GRANT EXECUTE ON FUNCTION update_receipt_shop TO anon;
