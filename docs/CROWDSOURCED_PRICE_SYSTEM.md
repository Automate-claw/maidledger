# MaidLedger — Crowdsourced Price System

**最後更新：** 2026-05-18
**用途：** 眾包價格數據庫架構文檔

---

## 📊 系統總覽

```
┌────────────────────────────────────────────────────────────────┐
│                    Crowdsourced Price System                      │
├────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐    ┌─────────────────┐    ┌──────────────┐ │
│  │  Chat Parser │───→│  Shop Matching  │───→│    Shops     │ │
│  │  (raw amount)│    │  + Alias Store  │    │  + Aliases   │ │
│  └──────────────┘    └─────────────────┘    └──────────────┘ │
│         │                                              │       │
│         ▼                                              ▼       │
│  ┌──────────────┐    ┌─────────────────┐    ┌──────────────┐ │
│  │Receipt Insert│───→│ Price History   │───→│ Price Alerts │ │
│  │              │    │   (per item)    │    │(weather sup.) │ │
│  └──────────────┘    └─────────────────┘    └──────────────┘ │
│                                                                  │
└────────────────────────────────────────────────────────────────┘
```

---

## 🗄️ Database Schema

### shops
標準化店舖/地點 entity

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| canonical_name | TEXT | 標準化名稱（如「惠康超市旺角店」）|
| shop_type | TEXT | supermarket/wet_market/pharmacy/convenience/online/restaurant/cafe/takeaway/other |
| region | TEXT | 九龍/港島/新界 |
| district | TEXT | 旺角/中環/沙田 |
| created_at | TIMESTAMPTZ | |

### shop_aliases
所有遇到的原始名稱

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| raw_name | TEXT | 原始名稱（如「惠康旺角店」）|
| shop_id | UUID | FK → shops |
| source | TEXT | ocr/crawler/manual/seed |
| created_at | TIMESTAMPTZ | |

### master_products
標準化產品定義

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| canonical_name | TEXT | 標準化名稱 |
| brand | TEXT | 品牌 |
| prd_cate | TEXT | 產品類別 |
| default_unit | TEXT | 默認單位 |
| search_keywords | TEXT[] | 搜索關鍵詞 |

### product_aliases
產品別名（支持多語言）

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| raw_name | TEXT | 原始名稱 |
| master_product_id | UUID | FK → master_products |
| source | TEXT | ocr/crawler/manual/seed |
| language_origin | TEXT | zh/en/tl/id/my/other |
| created_at | TIMESTAMPTZ | |

### price_history
價格歷史記錄

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| master_product_id | UUID | FK → master_products |
| shop_id | UUID | FK → shops |
| location | TEXT | 原始地點 |
| region | TEXT | 派生區域 |
| price | DECIMAL(10,2) | 價格 |
| unit | TEXT | 單位（如「斤」）|
| source_receipt_id | UUID | FK → receipts |
| recorded_at | DATE | 日期（無時間）|
| created_at | TIMESTAMPTZ | |

### weather_signals
天氣信號

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| signal_type | TEXT | T8/T3/AMBER/RED/BLACK |
| signal_name | TEXT | 信號名稱 |
| issued_at | TIMESTAMPTZ | 發出時間 |
| expired_at | TIMESTAMPTZ | 過期時間（null=仍有效）|

### price_alert_suppression
天氣抑制記錄

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| start_time | TIMESTAMPTZ | 抑制開始時間 |
| end_time | TIMESTAMPTZ | 抑制結束時間 |
| reason | TEXT | 原因（如「Typhoon T8」）|
| suppressed_categories | TEXT[] | 被抑制的類別（如 ['fish','vegetables']）|

---

## 🔄 比較邏輯（價格警報）

### 基線計算

| 情況 | 比較方式 | 基線 |
|------|---------|------|
| Day 0 | Cold start | 無比較 |
| Day 1-6 | vs 上次購買價 | 最近一次記錄的 price |
| Day 7+ | Rolling 7-day average | 過去7天平均價格 |

### 警報觸發條件

```
current_price > baseline * (1 + threshold)
threshold = 15%
```

---

## 🌧️ 天氣抑制機制

### 抑制條件
- 當有 active 的 `price_alert_suppression` record
- 且產品類別在 `suppressed_categories` 中
- 警報被跳過（weather_suppressed = true）

### 常見抑制場景
- T8 風球：抑制 fish + vegetables 類別
- 紅色暴雨：抑制蔬菜類別

---

## 🔍 多語言產品匹配

### 字典示例

```dart
multiLangFish = {
  'fish': ['魚', '魚類', '紅衫魚', '石斑', 'isda', 'ikan', 'fish', 'iping', 'bangus'],
  // 菲仲文: isda=魚, catfish=hito, milkfish=bangus
  // 印尼: ikan=魚, ikan mas=goldfish
}

multiLangMeat = {
  'pork': ['豬肉', '豬', 'carne', 'karne', 'baboy', 'daging babi'],
  'beef': ['牛肉', '牛', 'beef', 'carne de res', 'sapi'],
  'chicken': ['雞肉', '雞', 'chicken', 'manok', 'ayam'],
}
```

### 匹配流程
1. Exact alias match
2. ILIKE keyword match on canonical_name
3. Multi-language dictionary fallback
4. Auto-create if confidence >= 0.5

---

## 📁 關鍵檔案

```
supabase/
├── functions/
│   ├── chat-parser/index.ts          # Raw amount extraction + LLM
│   ├── price-alert-engine/index.ts   # Alert logic + weather suppression
│   └── weather-check/index.ts        # HK Observatory API check
└── migrations/
    ├── 013_shops_and_aliases.sql
    ├── 013b_product_aliases_language_origin.sql
    ├── 014_price_history.sql
    └── 015_price_alerts_enhanced.sql

apps/helper_app/lib/core/services/
├── shop_matching_service.dart        # Shop matching + alias creation
└── product_matching_service.dart     # Multi-language product matching
```

---

## 📝 修改記錄

| 日期 | 修改內容 |
|------|---------|
| 2026-05-18 | 加入 shops + shop_aliases tables |
| 2026-05-18 | 加入 shop_matching_service.dart |
| 2026-05-18 | 加入 multi-language product matching |
| 2026-05-18 | 加入 price_history table + write flow |
| 2026-05-18 | 加入 price-alert-engine + weather-check edge functions |