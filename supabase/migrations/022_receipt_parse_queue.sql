-- Migration: receipt_parse_queue
-- Fire-and-forget architecture: confirm 立即儲存 → 後台 LLM parse
-- 
-- 新增欄位：
--   ocr_raw_text       : 原始 OCR 文字
--   ocr_reconstructed : 重構文字 (Row-Reconstructed format)
--   parse_status      : pending | processing | parsed | needs_review | failed
--   parse_confidence  : LLM confidence score
--   needs_review      : true = 高金額/低信心 → 待雇主審核
--   reviewed_by       : 雇主確認邊個 review
--   reviewed_at       : 確認時間

ALTER TABLE receipts 
  ADD COLUMN IF NOT EXISTS ocr_raw_text TEXT,
  ADD COLUMN IF NOT EXISTS ocr_reconstructed TEXT,
  ADD COLUMN IF NOT EXISTS parse_status TEXT DEFAULT 'pending' 
    CHECK (parse_status IN ('pending', 'processing', 'parsed', 'needs_review', 'failed')),
  ADD COLUMN IF NOT EXISTS parse_confidence REAL,
  ADD COLUMN IF NOT EXISTS needs_review BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS reviewed_by UUID REFERENCES user_profiles(id),
  ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ;

-- Index for background job polling
CREATE INDEX IF NOT EXISTS idx_receipts_parse_status_pending 
  ON receipts(parse_status) WHERE parse_status = 'pending';