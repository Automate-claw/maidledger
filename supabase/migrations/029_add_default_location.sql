-- Add default_location column to user_profiles for helpers
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS default_location TEXT;

-- Allow helpers to update their own default_location
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Helpers can update own profile" ON user_profiles;
CREATE POLICY "Helpers can update own profile"
  ON user_profiles FOR UPDATE
  USING (auth.uid() = id AND role = 'helper')
  WITH CHECK (auth.uid() = id);

COMMENT ON COLUMN user_profiles.default_location IS 'Default district/region for helper, used when no GPS EXIF available';