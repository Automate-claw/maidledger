-- Migration: 018_allow_authenticated_insert_master_products
-- Allow authenticated users to INSERT master_products (for their own unmatched items)
-- SELECT is already allowed (anyone can read catalog)
-- DELETE/UPDATE still restricted to service_role only

-- Insert policy: authenticated users can create new master products
CREATE POLICY "Authenticated users can insert master_products"
ON public.master_products
FOR INSERT
TO authenticated
WITH CHECK (true);

-- Update policy: users can only update their own entries (future use)
CREATE POLICY "Users can update own master_products"
ON public.master_products
FOR UPDATE
TO authenticated
USING (auth.uid() IS NOT NULL)
WITH CHECK (auth.uid() IS NOT NULL);
