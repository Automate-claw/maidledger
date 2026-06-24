-- Migration 042: Community Badges / Gamification
-- Awards "精明眼" badges to households that outperform their district average

CREATE TABLE IF NOT EXISTS community_badges (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employer_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  badge_type TEXT NOT NULL,           -- 'smart_eye_weekly' | 'smart_eye_monthly'
  district TEXT NOT NULL,             -- e.g. '將軍澳區' | '沙田區'
  period_start DATE NOT NULL,
  period_end DATE NOT NULL,
  savings_vs_district DECIMAL(10, 2), -- estimated savings vs district average
  percentile_rank DECIMAL(5, 2),       -- e.g. 95.0 = top 5%
  total_spent DECIMAL(10, 2),          -- total spend in period
  district_avg_spent DECIMAL(10, 2),  -- district average for comparison
  awarded_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(employer_id, badge_type, period_start)
);

CREATE INDEX IF NOT EXISTS idx_badges_employer
  ON community_badges(employer_id, period_start DESC);
CREATE INDEX IF NOT EXISTS idx_badges_district
  ON community_badges(district, period_start DESC);
CREATE INDEX IF NOT EXISTS idx_badges_type
  ON community_badges(badge_type, period_start DESC);

COMMENT ON TABLE community_badges IS
  'Awarded badges for outperforming district averages. Shown in app as encouragement.';
