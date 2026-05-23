-- ══════════════════════════════════════════════════════════════════════════════
-- 024_receipt_items_brand_spec.sql
--
-- B2B 數據變現擴展：為 receipt_items 添加結構化欄位
--
-- ▸ extracted_brand — 標準化品牌名（如：759阿信屋 / 維記 / 雀巢）
-- ▸ extracted_name — 純產品核心名稱（不含品牌、容量、店鋪特異字眼）
-- ▸ extracted_spec — 規格/容量（如：946ml / 10卷裝 / 大號），無則 null
--
-- item_name 保持不變（向後兼容），meaning 改為「LLM 原始輸出（可能含有噪音）」
-- extracted_name 是清洗後的純產品核心名稱
--
-- 效果：
--   原本：item_name = "759阿信屋圣擊袋 大號"（混沌）
--   優化後：extracted_brand="759阿信屋" / extracted_name="聖擊袋" / extracted_spec="大號"
--           keyword matching 可以用「聖擊袋」精準匹配，數據可以直接出售
-- ══════════════════════════════════════════════════════════════════════════════

ALTER TABLE public.receipt_items
  ADD COLUMN IF NOT EXISTS extracted_brand TEXT,
  ADD COLUMN IF NOT EXISTS extracted_name TEXT,
  ADD COLUMN IF NOT EXISTS extracted_spec TEXT;

COMMENT ON COLUMN public.receipt_items.extracted_brand IS '標準化品牌名稱（如：759阿信屋 / 維記 / 雀巢），從 LLM 結構化解析取得';
COMMENT ON COLUMN public.receipt_items.extracted_name  IS '純產品核心名稱，不含品牌、容量、店鋪特異字眼（如：鮮牛奶 / 濕紙巾 / 聖擊袋）';
COMMENT ON COLUMN public.receipt_items.extracted_spec  IS '規格或容量（如：946ml / 10卷裝 / 大號），無則 null';
COMMENT ON COLUMN public.receipt_items.item_name     IS 'LLM 原始輸出（含品牌/容量/店鋪特異字眼），兼容性保留；建議使用 extracted_name 做匹配';