# 全港物價比價 — 產品Matching架構

## 目標
用最少用戶介入，實現跨網店 / 跨 OCR 收據嘅商品自動對齊（Entity Resolution）

---

## 最終目標架構（Vector 版本）

### 資料庫 Schema

```sql
-- 1. 核心標準商品表（Master Product）
CREATE TABLE master_products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  canonical_name TEXT NOT NULL,           -- 標準名：維他檸檬茶 250ml
  brand TEXT,                             -- 維他
  prd_cate TEXT REFERENCES prd_categories(code), -- fish, drink, etc.
  default_unit TEXT,                      -- ml, g, 斤, 件
  embedding VECTOR(1536),                 -- OpenAI text-embedding-3-small
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. 商品別名表（所有遇過的原始名稱）
CREATE TABLE product_aliases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  raw_name TEXT UNIQUE NOT NULL,          -- VLT 250ml, 維他檸標茶 25Oml
  master_product_id UUID REFERENCES master_products(id) ON DELETE CASCADE,
  source TEXT,                            -- 'ocr' | 'crawler' | 'manual'
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. 現有 receipt_items 加關聯
ALTER TABLE receipt_items ADD COLUMN master_product_id UUID REFERENCES master_products(id);
```

### 自動化對齊流程（Three-Tier Matching）

```
User Scan → AI Parse items
                │
        ┌─ Step 1: Exact Match ──────────┐
        │  查 product_aliases(raw_name)  │
        │  ✅ Hit → 直接用 master_product_id
        │  ❌ Miss → 下一步
        └───────────────────────────────┘
                │
        ┌─ Step 2: Embedding Search ─────┐
        │  新品名 → 轉 vector             │
        │  Cosine Similarity > 0.85     │
        │  ✅ 找到 → 自動寫入 aliases     │
        │  ❌ 低於門檻 → 下一步           │
        └───────────────────────────────┘
                │
        ┌─ Step 3: New Master Product ───┐
        │  判定為新商品                   │
        │  自動創建 master_products       │
        │  raw_name 自己 bind 自己        │
        └───────────────────────────────┘
```

---

## MVP 版本（ILIKE，無 pgvector dependency）

### 資料庫 Schema

```sql
-- 1. 核心標準商品表
CREATE TABLE master_products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  canonical_name TEXT NOT NULL,           -- 標準名：維他檸檬茶 250ml
  brand TEXT,                             -- 維他
  prd_cate TEXT,                          -- 對應 prd_categories.code
  default_unit TEXT,                      -- ml, g, 斤, 件
  search_keywords TEXT[],                  -- ['維他', '檸檬', '茶', '250ml'] -- ILIKE 用
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. 商品別名表
CREATE TABLE product_aliases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  raw_name TEXT UNIQUE NOT NULL,
  master_product_id UUID REFERENCES master_products(id) ON DELETE CASCADE,
  source TEXT,                            -- 'ocr' | 'crawler' | 'manual'
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. 現有 receipt_items 加關聯
ALTER TABLE receipt_items ADD COLUMN master_product_id UUID REFERENCES master_products(id);

-- Index for ILIKE performance
CREATE INDEX idx_master_products_search ON master_products USING GIN(to_tsvector('simple', canonical_name));
```

### MVP 匹配邏輯（Edge Function 或 Flutter service）

```
Step 1: exact match in product_aliases
        → SELECT master_product_id FROM product_aliases WHERE raw_name = {item_name}

        MISS → Step 2

Step 2: ILIKE keyword match
        → canonical_name ILIKE '%{keyword1}%' AND canonical_name ILIKE '%{keyword2}%'
        → 按 brand + prd_cate 過濾
        → confidence = matched_keywords_count / total_keywords

        CONFIDENT (>3 keywords match) → auto-bind
        UNCLEAR → Step 3

Step 3: New product
        → 自動創建 master_products（用 item_name 作 canonical_name）
        → 同時寫 self-referencing alias
```

---

## 初始種子資料（Seed Data）

系统启动时需要 initial master_products，可以：

1. **淘寶暢銷商品** — 淘寶 API 或網店爬蟲
2. **超市官網商品目錄** — 百佳、惠康、Mannings 官網
3. **LLM batch generate** — 列出香港常見商品 top 200-500，讓 LLM 生成 canonical_name + brand + prd_cate

建議先用方案3，成本最低（一次 API call）。

---

## Supabase pgvector 安裝確認

```sql
-- 確認是否已安裝
SELECT * FROM pg_extension WHERE extname = 'vector';

-- 安裝（需要 Supabase Pro Tier + DB restart）
CREATE EXTENSION IF NOT EXISTS vector;
```

確認後再升級 embedding column。

---

## 優先順序

| 階段 | 工作 | Dependency |
|------|------|-----------|
| 1    | 加 master_products + product_aliases table | 無 |
| 1    | receipt_items 加 master_product_id column | 無 |
| 1    | ILIKE matching logic (Flutter/Edge) | 無 |
| 1    | Seed initial master_products (top 200 HK items) | LLM API |
| 2    | 安裝 pgvector | 需要 Pro Tier |
| 2    | 加 embedding column + HNSW index | pgvector |
| 2    | 升級 matching logic 做 vector search | pgvector |

---

## 費用估算（Vector 版本上綫後）

- Supabase Disk: 60 MB / 500 MB FREE（10,000 master_products）
- OpenRouter Embedding: ~HK$0.3/日（10,000 scans × 20 items）
- 90% 第一層 exact match 攔截，實際 embedding call 係 10%