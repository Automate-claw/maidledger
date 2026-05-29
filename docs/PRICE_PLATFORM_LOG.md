# 日用品價格平台 - 執行日誌

## 最後更新：2026-05-30

---

## Phase 1：數據層

### Task 1.1：建立 cc_prices table ✅

**日期：** 2026-05-27
**狀態：** ✅ COMPLETED

**Migration:** `supabase/migrations/028_price_platform_cc_prices.sql`

**Schema：**
```sql
cc_prices (
  cc_code           TEXT PRIMARY KEY,
  name_en           TEXT,
  name_zh           TEXT,
  brand_en          TEXT,
  brand_zh          TEXT,
  cat1_en/zh        TEXT,
  cat2_en/zh        TEXT,
  cat3_en/zh        TEXT,
  prices            JSONB,
  standard_weight_g  INTEGER,
  price_per_100g     DECIMAL,
  updated_at        TIMESTAMPTZ
)
```

---

### Task 1.2：fetch-cc-prices ✅

**日期：** 2026-05-27
**狀態：** ✅ COMPLETED

**Script：** `scripts/fetch_cc_prices.py`
**Result:** ✅ 2542 records inserted in 2.4s

---

### Task 1.3：receipt_items Schema 更新 ✅

**狀態：** ✅ COMPLETED

**新增欄位：**
```sql
receipt_items (
  weight_grams       DECIMAL,
  price_per_gram     DECIMAL,
  cc_code            TEXT,
  cc_price_per_gram  DECIMAL,
  subcategory_code   TEXT  -- 新增：2026-05-28
)
```

---

### Task 1.4：user_profiles Schema 更新 ✅

**狀態：** ✅ COMPLETED

**新增欄位：**
```sql
user_profiles (
  household_size INTEGER
)
```

---

### Task 1.5：subcategories + weight_options ✅ **NEW 2026-05-28**

**Migration:** `029_subcategories_and_weight_options.sql`

**Architecture：**
```
prd_categories (12種，高層分析)
    ↓
subcategories (細分，整個零售生態)
    ↓
weight_options (每個 subcategory 對應嘅 weight list)
    ↓
master_products (綁定 subcategory)
    ↓
cc_prices + community_prices (價格數據)
```

**Schema：**
```sql
subcategories (
  id SERIAL PRIMARY KEY,
  code TEXT UNIQUE NOT NULL,       -- 'fresh_fish', 'fish_ball'
  name_tc TEXT NOT NULL,          -- '新鮮魚', '魚肉丸/魚蛋'
  name_en TEXT,
  parent_cate TEXT REFERENCES prd_categories(code),  -- 'fish'
  display_order INT DEFAULT 0
)

weight_options (
  id SERIAL PRIMARY KEY,
  subcategory_code TEXT REFERENCES subcategories(code),
  weight_g INTEGER NOT NULL,       -- 170, 500, 604
  label TEXT NOT NULL,            -- '170g', '1斤 (605g)', '6粒'
  unit_type TEXT DEFAULT 'g' CHECK (unit_type IN ('g', 'pcs', 'kg')),
  display_order INT DEFAULT 0
)
```

**Subcategories 現有數據（38種）：**
| 當前分類 | subcategories 代碼 |
|---------|-------------------|
| fish | fresh_fish, fish_fillet, fish_ball, dried_fish, fish_tofu |
| pork | pork_belly, pork_loin, pork_trotter, pork_offal |
| beef | beef_fillet, beef_shin, beef_offal |
| chicken | chicken_whole, chicken_breast, chicken_offal |
| vegetables | veg_leafy, veg_root, veg_fruit, veg_mushroom, veg_bean |
| rice | rice, noodle, flour |
| oil | oil_cooking, oil_special |
| seasoning | season_sauces, season_herbs, season_stock |
| snack | snack_sweet, snack_salty, snack_nuts |
| drink | drink_soft, drink_tea, drink_juice, drink_milk |
| daily | daily_cleaning, daily_paper, daily_personal, daily_kitchen, daily_other |

**好處：**
- 物價分析粒度到 subcategory
- 新鮮魚 VS 魚丸 VS 魚片完全分開分析
- 雞蛋可以用「粒」做單位

---

## Phase 2：LLM Enhancement

### Task 2.1：chat-parser 優化 ⏳ **IN PROGRESS**

**目標：** LLM 返回時包含：
```json
{
  "item_name": "魚肉丸",
  "amount": 25,
  "prd_cate": "fish",
  "subcategory_code": "fish_ball",
  "weight_options": [170, 250, 300, 500, 6, 12, 20],
  "unit": "g",
  "cc_match": {
    "cc_code": "P000002614",
    "cc_name": "魚肉丸 170克",
    "standard_weight_g": 170,
    "price_per_100g": 11.76,
    "confidence": 0.85
  }
}
```

**流程：**
```
傭人輸入：「魚肉丸 $25」
    ↓
本地即時 Save（pending）
    ↓
LLM 分析（1-3秒）
    ↓
回傳 subcategory_code（'fish_ball'）
    ↓
Flutter query：SELECT weight_g, label, unit_type FROM weight_options WHERE subcategory_code='fish_ball' ORDER BY display_order
    ↓
顯示：[170g] [250g] [300g] [500g] [6粒] [12粒] [20粒]
    ↓
傭人揀 → 更新 receipt_items.subcategory_code + weight_grams
```

**注意：** 目前 chat-parser 第 296 行有個 bug：`takeaway` 不在 `prd_categories` 中，需修復。

---

## Phase 3：Flutter UI

### Task 3.1：Weight Selector Widget

**狀態：** PENDING

**流程：**
```
傭人輸入：「魚肉丸 $25」
    ↓
本地即時 Save ✅
    ↓
LLM 分析（1-3秒）
    ↓
顯示：[170g] [250g] [300g] [500g] chips
    ↓
傭人揀 → Save subcategory_code + weight_grams
    ↓
顯示 Comparison（actual vs CC）
```

---

## Phase 4：社區數據（長遠）

**狀態：** BACKLOG

**目標：** 建立街市 community price（用戶上報）

---

## 重要發現

1. **CC 數據限制：** 消委會主要係超市數據，新鮮魚（紅衫魚、黃立鯧）沒有
2. **魚類覆蓋：** CC 只有加工魚製品（魚丸、魚蛋），無新鮮魚
3. **街市數據：** 需要靠用戶上報建立 community data

---

## 下一步

1. [x] Task 1.5：建立 subcategories + weight_options migration
2. [ ] Task 2.1：chat-parser LLM prompt 更新 + 修復 `takeaway` bug
3. [ ] Task 3.1：Flutter Weight Selector UI
