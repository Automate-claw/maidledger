-- Migration 038: RPC function for cross-household price aggregation
-- This function aggregates normalized_unit_price from multiple households
-- Returns aggregated stats without exposing individual household data
--
-- Parameters:
--   p_standard_name: product standard name to filter
--   p_employer_ids: array of trusted employer IDs
--   p_cutoff_time: timestamp cutoff (e.g. 48 hours ago)
--   p_district: optional district filter
--   p_store_type: optional store type filter
--   p_min_data_points: minimum data points required

CREATE OR REPLACE FUNCTION get_cross_household_prices(
  p_standard_name TEXT,
  p_employer_ids UUID[],
  p_cutoff_time TIMESTAMPTZ,
  p_district TEXT DEFAULT NULL,
  p_store_type TEXT DEFAULT NULL,
  p_min_data_points INT DEFAULT 10
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSON;
  v_count INT;
  v_household_count INT;
BEGIN
  -- Get count of distinct households first
  SELECT
    COUNT(DISTINCT r.employer_id),
    COUNT(ri.normalized_unit_price)
  INTO v_household_count, v_count
  FROM receipt_items ri
  JOIN receipts r ON r.id = ri.receipt_id
  JOIN shops s ON s.id = r.shop_id
  WHERE ri.standard_name ILIKE '%' || p_standard_name || '%'
    AND ri.normalized_unit_price IS NOT NULL
    AND ri.confidence_score >= 0.5
    AND r.employer_id = ANY(p_employer_ids)
    AND r.created_at >= p_cutoff_time
    AND (p_district IS NULL OR r.location ILIKE '%' || p_district || '%')
    AND (p_store_type IS NULL OR s.shop_type = p_store_type);

  IF v_count < p_min_data_points OR v_household_count < 5 THEN
    RETURN json_build_object(
      'success', true,
      'available', false,
      'reason', 'Not enough data points or households',
      'data_point_count', v_count,
      'household_count', v_household_count
    );
  END IF;

  -- Compute aggregated statistics
  SELECT json_build_object(
    'median', PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ri.normalized_unit_price),
    'avg', AVG(ri.normalized_unit_price),
    'min', MIN(ri.normalized_unit_price),
    'max', MAX(ri.normalized_unit_price),
    'count', v_count,
    'household_count', v_household_count,
    'percentile_25', PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY ri.normalized_unit_price),
    'percentile_75', PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY ri.normalized_unit_price)
  )
  INTO v_result
  FROM receipt_items ri
  JOIN receipts r ON r.id = ri.receipt_id
  JOIN shops s ON s.id = r.shop_id
  WHERE ri.standard_name ILIKE '%' || p_standard_name || '%'
    AND ri.normalized_unit_price IS NOT NULL
    AND ri.confidence_score >= 0.5
    AND r.employer_id = ANY(p_employer_ids)
    AND r.created_at >= p_cutoff_time
    AND (p_district IS NULL OR r.location ILIKE '%' || p_district || '%')
    AND (p_store_type IS NULL OR s.shop_type = p_store_type);

  RETURN json_build_object(
    'success', true,
    'available', true,
    'standard_name', p_standard_name,
    'aggregated', v_result,
    'source', 'cross_household_48h',
    'confidence', CASE
      WHEN v_count >= 50 AND v_household_count >= 20 THEN 0.9
      WHEN v_count >= 20 AND v_household_count >= 10 THEN 0.75
      ELSE 0.6
    END,
    'freshness_window', '48h',
    'note', 'Prices from anonymous neighbors. Individual households not identified.'
  );
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION get_cross_household_prices TO authenticated;
GRANT EXECUTE ON FUNCTION get_cross_household_prices TO anon;
