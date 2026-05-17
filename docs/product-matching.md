# 全港物價比價 — 產品 Matching 架構

## 目標
用最少用戶介入，實現跨網店 / 跨 OCR 收據嘅商品自動對齊（Entity Resolution）

---

## ✅ Phase 1 已完成（ILIKE MVP）

### 資料庫 Schema（已部署）

```sql
-- 1. 核心標準商品表
CREATE TABLE master_products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  canonical_name TEXT NOT NULL,           -- 標準名：維他檸檬茶 250ml
  brand TEXT,                             -- 維他
  prd_cate TEXT,                          -- 對應 prd_categories.code
  default_unit TEXT,                      -- ml, g, 斤, 件
  search_keywords TEXT[],                  -- ILIKE 用（目前未自動填充）
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. 商品別名表（所有遇過的原始名稱）
CREATE TABLE product_aliases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  raw_name TEXT UNIQUE NOT NULL,          -- VLT 250ml, 維他檸標茶 25Oml
  master_product_id UUID REFERENCES master_products(id) ON DELETE CASCADE,
  source TEXT,                            -- 'ocr' | 'crawler' | 'manual' | 'seed'
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. receipt_items 已加 master_product_id
ALTER TABLE receipt_items ADD COLUMN master_product_id UUID REFERENCES master_products(id);
```

### 已實作流程（Flutter Service）

```
User Scan → AI Parse items
                │
        ┌─ Step 1: Exact Alias Match ─────┐
        │  查 product_aliases(raw_name)  │
        │  ✅ Hit → bind master_product_id
        │  ❌ Miss → Step 2              │
        └────────────────────────────────┘
                │
        ┌─ Step 2: ILIKE Keyword Match ──┐
        │  textSearch(canonical_name)    │
        │  confidence >= 0.5 → bind     │
        │  + auto-create alias          │
        │  ❌ Miss → Step 3              │
        └────────────────────────────────┘
                │
        ┌─ Step 3: New Product ──────────┐
        │  自動創建 master_products      │
        │  raw_name self-bind alias      │
        └────────────────────────────────┘
```

### 檔案

| 檔案 | 用途 |
|------|------|
| `supabase/migrations/012_master_products_and_aliases.sql` | DB schema |
| `apps/helper_app/lib/core/services/product_matching_service.dart` | ILIKE matching service |

---

## Phase 2：pgvector Embedding 升級

### 需做的事情

1. **安裝 pgvector**
   ```sql
   CREATE EXTENSION IF NOT EXISTS vector;
   ```

2. **加 embedding column**
   ```sql
   ALTER TABLE master_products ADD COLUMN embedding VECTOR(1536);
   CREATE INDEX ON master_products USING HNSW(embedding);
   ```

3. **升級 matching logic**
   - Step 2 改為向量搜尋（Cosine Similarity > 0.85）
   - 每次新 master_product 創建時 call embedding API 填 vector

4. **費用**
   - Supabase: $0（用免費額度，10,000 products ≈ 60MB）
   - OpenRouter Embedding: ~HK$0.3/日（10,000 scans × 20 items）
   - 90% 流量第一層 exact match 攔截

---

## 初始種子資料（Seed Data）

### 建議方案：LLM Batch Generate

用 LLM 生成香港常見商品 top 200-500：
- 超市：維他檸檬茶、雞蛋、豬肉、米、油、鹽
- 街市：紅衫魚、菜心、牛肉、洋蔥
- 便利店：飯糰、罐頭、零食、飲品

```json
// 範例 output
{
  "canonical_name": "維他檸檬茶 250ml",
  "brand": "維他",
  "prd_cate": "drink",
  "default_unit": "ml"
}
```

### 執行方式

1. Edge function 或 Flutter service batch insert
2. 或直接 SQL INSERT from CSV

---

## 參考：最終目標架構

```sql
CREATE TABLE master_products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  canonical_name TEXT NOT NULL,
  brand TEXT,
  prd_cate TEXT REFERENCES prd_categories(code),
  default_unit TEXT,
  embedding VECTOR(1536),   -- pgvector
  created_at TIMESTAMPTZ DEFAULT now()
);
```

---

## 優先順序

| 階段 | 工作 | 狀態 |
|------|------|------|
| 1 | master_products + product_aliases table | ✅ 已完成 |
| 1 | receipt_items.master_product_id column | ✅ 已完成 |
| 1 | ILIKE matching logic (Flutter) | ✅ 已完成 |
| 2 | 安裝 pgvector | 待辨 |
| 2 | 加 embedding column + HNSW index | 待辨 |
| 2 | 升級 matching logic 做 vector search | 待辨 |
| 3 | Seed initial master_products (top 200 HK items) | 待辨 |
| 3 | 網店爬蟲接入同一 matching 流程 | 待辨 |