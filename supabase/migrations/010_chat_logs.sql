-- Migration: 010_chat_logs
-- Records every chat-parser edge function call for debugging and analytics

CREATE TABLE IF NOT EXISTS public.chat_logs (
  id UUID DEFAULT gen_random_uuid(),
  user_id TEXT,
  input_text TEXT,
  output_response JSONB,
  is_expense BOOLEAN,
  completeness TEXT,
  total_amount NUMERIC,
  parse_confidence NUMERIC,
  llm_model_used TEXT,
  llm_raw_response TEXT,
  duration_ms INTEGER,
  error TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Index on user_id for user-level queries
CREATE INDEX IF NOT EXISTS idx_chat_logs_user_id ON public.chat_logs(user_id);

-- Index on created_at for time-series queries
CREATE INDEX IF NOT EXISTS idx_chat_logs_created_at ON public.chat_logs(created_at DESC);

-- Index on is_expense for analytics
CREATE INDEX IF NOT EXISTS idx_chat_logs_is_expense ON public.chat_logs(is_expense);

-- RLS: service_role can do anything; anon can only read own logs
ALTER TABLE public.chat_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "service_role_all" ON public.chat_logs;
CREATE POLICY "service_role_all" ON public.chat_logs FOR ALL USING (true) WITH CHECK (true);

-- Allow users to read their own logs
DROP POLICY IF EXISTS "users_read_own" ON public.chat_logs;
CREATE POLICY "users_read_own" ON public.chat_logs FOR SELECT USING (auth.uid()::text = user_id);

-- Allow users to insert their own logs
DROP POLICY IF EXISTS "users_insert_own" ON public.chat_logs;
CREATE POLICY "users_insert_own" ON public.chat_logs FOR INSERT WITH CHECK (auth.uid()::text = user_id);