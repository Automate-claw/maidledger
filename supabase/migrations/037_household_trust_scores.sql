-- Migration 037: Household Trust Score
-- Measures reliability of each household's price data
-- Used to weight their contribution in cross-household averages
--
-- trust_score = weighted(ocr_accuracy, correction_rate, entry_frequency)
-- Range: 0.0 to 1.0
--   < 0.3: Low — exclude from crowdsourced averages
--   0.3-0.6: Medium — reduced weight in aggregation
--   > 0.6: High — full weight

CREATE TABLE IF NOT EXISTS household_trust_scores (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employer_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  trust_score DECIMAL(3, 2) NOT NULL DEFAULT 0.5 CHECK (trust_score BETWEEN 0 AND 1),
  total_entries INT NOT NULL DEFAULT 0,        -- total receipt items submitted
  correct_entries INT NOT NULL DEFAULT 0,        -- entries not flagged/corrected
  correction_count INT NOT NULL DEFAULT 0,       -- employer corrections made
  last_updated TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(employer_id)
);

CREATE INDEX IF NOT EXISTS idx_trust_score
  ON household_trust_scores(trust_score DESC);

-- Trust score update function (called when receipts are processed/corrected)
-- Formula: trust_score = (correct_entries / NULLIF(total_entries,0)) * 0.7
--                                 + (1 - correction_rate) * 0.2
--                                 + normalized_frequency * 0.1
-- Simplified: trust_score = correct_rate * 0.7 + (1-correction_rate) * 0.2
--             clamped to [0.0, 1.0]
COMMENT ON TABLE household_trust_scores IS
  'Household trust score for crowdsourced data quality. trust_score < 0.3 = excluded from cross-household averages.';
