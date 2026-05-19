-- shops table INSERT policy for authenticated users
CREATE POLICY "allow_authenticated_insert_shops"
  ON shops FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

-- shop_aliases INSERT policy
CREATE POLICY "allow_authenticated_insert_shop_aliases"
  ON shop_aliases FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

-- product_aliases INSERT policy (already has one, but check)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'product_aliases' AND policyname = 'allow_authenticated_insert_product_aliases'
  ) THEN
    CREATE POLICY "allow_authenticated_insert_product_aliases"
      ON product_aliases FOR INSERT
      WITH CHECK (auth.role() = 'authenticated');
  END IF;
END
$$;

-- master_products INSERT policy (already has one)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'master_products' AND policyname = 'allow_authenticated_insert_master_products'
  ) THEN
    CREATE POLICY "allow_authenticated_insert_master_products"
      ON master_products FOR INSERT
      WITH CHECK (auth.role() = 'authenticated');
  END IF;
END
$$;
