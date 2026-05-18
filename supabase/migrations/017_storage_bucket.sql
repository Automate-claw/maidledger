-- Migration: 017_storage_bucket
-- Create receipts storage bucket with proper RLS policies

BEGIN;

-- Create receipts bucket (if not exists)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'receipts',
  'receipts',
  true,  -- public: true means anyone with URL can view (no auth needed for public URL)
  10485760,  -- 10MB limit
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- Enable RLS on storage.objects
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- Policy: anyone can upload receipts (authenticated users only)
CREATE POLICY "authenticated_users_can_upload_receipts"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'receipts'
  AND auth.role() = 'authenticated'
);

-- Policy: anyone can read receipts (public URL access)
CREATE POLICY "anyone_can_read_receipts"
ON storage.objects FOR SELECT
USING (bucket_id = 'receipts');

-- Policy: users can delete their own receipt objects
CREATE POLICY "users_can_delete_own_receipts"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'receipts'
  AND auth.uid() = owner
);

COMMIT;
