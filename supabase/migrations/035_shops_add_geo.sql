-- Migration 035: Add geo coordinates to shops for district clustering
-- Enables geo-based price comparison: "same market radius 1.5km" queries

ALTER TABLE shops
  ADD COLUMN IF NOT EXISTS latitude DECIMAL(10, 7),
  ADD COLUMN IF NOT EXISTS longitude DECIMAL(10, 7),
  ADD COLUMN IF NOT EXISTS geo_source TEXT;  -- 'gps_exif' | 'reverse_geocode' | 'manual' | 'afcd_market_list'

CREATE INDEX IF NOT EXISTS idx_shops_geo
  ON shops(latitude, longitude)
  WHERE latitude IS NOT NULL AND longitude IS NOT NULL;

COMMENT ON COLUMN shops.latitude IS 'GPS latitude (WGS84) from receipt EXIF or reverse geocode';
COMMENT ON COLUMN shops.longitude IS 'GPS longitude (WGS84)';
