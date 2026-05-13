-- Price Alert Edge Functions for Supabase
-- Handles real-time price comparison

CREATE OR REPLACE FUNCTION get_price_alert(
  p_category TEXT,
  p_price REAL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_avg_price REAL;
  v_min_price REAL;
  v_max_price REAL;
  v_supermarket_avg REAL;
  v_difference REAL;
  v_alert_level TEXT;
BEGIN
  -- Get average price for category from last 7 days
  SELECT AVG(price), MIN(price), MAX(price)
  INTO v_avg_price, v_min_price, v_max_price
  FROM price_data
  WHERE category = p_category
    AND scraped_at > NOW() - INTERVAL '7 days';

  -- Get supermarket-specific average
  SELECT AVG(price)
  INTO v_supermarket_avg
  FROM (
    SELECT supermarket, AVG(price) as avg_price
    FROM price_data
    WHERE category = p_category
      AND scraped_at > NOW() - INTERVAL '7 days'
    GROUP BY supermarket
  ) sub;

  -- Calculate difference
  IF v_avg_price IS NOT NULL AND v_avg_price > 0 THEN
    v_difference := ((p_price - v_avg_price) / v_avg_price) * 100;

    -- Determine alert level
    IF v_difference < -10 THEN
      v_alert_level := 'green';  -- Much cheaper than average
    ELSIF v_difference < 5 THEN
      v_alert_level := 'green';  -- Slightly cheaper or normal
    ELSIF v_difference < 20 THEN
      v_alert_level := 'yellow'; -- Slightly expensive
    ELSE
      v_alert_level := 'red';    -- Much more expensive
    END IF;
  ELSE
    v_difference := 0;
    v_alert_level := 'unknown';
  END IF;

  RETURN jsonb_build_object(
    'category', p_category,
    'input_price', p_price,
    'avg_price', ROUND(v_avg_price::numeric, 2),
    'min_price', v_min_price,
    'max_price', v_max_price,
    'difference_percent', ROUND(v_difference::numeric, 1),
    'alert_level', v_alert_level,
    'message', CASE
      WHEN v_difference < -10 THEN '✅ 比超市平好多！'
      WHEN v_difference < 5 THEN '✅ 正常價'
      WHEN v_difference < 20 THEN '⚠️ 偏貴'
      ELSE '🚨 貴過超市好多！'
    END
  );
END;
$$;

-- Parse receipt text with LLM (calls Gemini)
CREATE OR REPLACE FUNCTION parse_receipt_text(
  p_raw_text TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result JSONB;
BEGIN
  -- This would call Gemini Edge Function
  -- For now, return structured placeholder
  v_result := jsonb_build_object(
    'items', ARRAY[]::TEXT[],
    'total', NULL,
    'category', 'food',
    'confidence', 0.5
  );

  RETURN v_result;
END;
$$;