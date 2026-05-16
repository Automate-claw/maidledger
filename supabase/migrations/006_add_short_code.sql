-- Migration: Add short_code to user_profiles
-- Generates unique 6-char codes for employer invite flow

-- 1. Add short_code column (VARCHAR for flexibility)
ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS short_code VARCHAR(20) UNIQUE;

-- 2. Function to generate unique 6-char alphanumeric code
CREATE OR REPLACE FUNCTION generate_short_code()
RETURNS VARCHAR(6)
LANGUAGE plpgsql
AS $$
DECLARE
  v_code VARCHAR(6);
  v_exists BOOLEAN;
BEGIN
  -- Generate until unique (handles collisions)
  LOOP
    v_code := UPPER(
      SUBSTRING(
        'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' FROM
        floor(random() * 28)::int + 1 FOR 1
      ) ||
      SUBSTRING(
        'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' FROM
        floor(random() * 28)::int + 1 FOR 1
      ) ||
      SUBSTRING(
        'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' FROM
        floor(random() * 28)::int + 1 FOR 1
      ) ||
      SUBSTRING(
        'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' FROM
        floor(random() * 28)::int + 1 FOR 1
      ) ||
      SUBSTRING(
        'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' FROM
        floor(random() * 28)::int + 1 FOR 1
      ) ||
      SUBSTRING(
        'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' FROM
        floor(random() * 28)::int + 1 FOR 1
      )
    );

    SELECT EXISTS(SELECT 1 FROM user_profiles WHERE short_code = v_code) INTO v_exists;
    IF NOT v_exists THEN
      RETURN v_code;
    END IF;
  END LOOP;
END;
$$;

-- 3. Update existing profiles without short_code
UPDATE user_profiles
SET short_code = generate_short_code()
WHERE short_code IS NULL;

-- 4. Update handle_new_user trigger to also set short_code
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.user_profiles (id, role, name, short_code)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'role', 'helper'),
    COALESCE(
      NEW.raw_user_meta_data->>'name',
      NEW.raw_user_meta_data->>'full_name',
      NEW.email
    ),
    generate_short_code()  -- Add this line
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;