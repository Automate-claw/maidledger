# MaidLedger — Price Anchor System（價格錨點系統）

**最後更新：** 2026-06-24
**用途：** 記錄 MaidLedger 的價格比較引擎設計
**基於：** Gemini 建議 + 跨家庭比較框架

---

## 📊 系統總覽

```
┌─────────────────────────────────────────────────────────────────┐
│                  Price Anchor System Architecture                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────┐    ┌─────────────────┐    ┌────────────────┐ │
│  │receipt-parse │───→│ receipt-writer │───→│ receipt_items  │ │
│  │(LLM Vision) │    │                 │    │ + normalized   │ │
│  └──────────────┘    └─────────────────┘    └───────┬────────┘ │
│                                                      │          │
│                              ┌──────────────────────┘          │
│                              ▼                                  │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │              Price Reference Engine                        │ │
│  │  四層 Anchor Priority（由最精準到最通用）                     │ │
│  │  Layer 0: Geo Cluster（同街市 1.5km, 48h）                 │ │
│  │  Layer 1: Consumer Council Median（超市包裝貨）              │ │
│  │  Layer 2: Own Trimmed Mean（45天, freshness weighted）      │ │
│  │  Layer 3: AFCD Wholesale × 2.0（生鮮/LLM 兜底）           │ │
│  └──────────────────────────────────────────────────────────┘ │
│                              │                                  │
│                              ▼                                  │
│  ┌──────────────┐    ┌─────────────────┐    ┌────────────────┐ │
│  │price-alert-  │───→│  Buffer Zone    │───→│ Price Alerts   │ │
│  │engine        │    │  判定 + 人性化   │    │ + humanized msg│ │
│  └──────────────┘    └─────────────────┘    └───────┬────────┘ │
│                                                      │          │
│                              ┌──────────────────────┘          │
│                              ▼                                  │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │           Cross-Household Query（匿名聚合）                 │ │
│  │  48h 窗口 / 最少 5 家庭 10 數據點 / trust_score ≥ 0.3   │ │
│  └──────────────────────────────────────────────────────────┘ │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔢 統一比較公式

**所有比較以 `normalized_unit_price` 為唯一基準。**

```
D = (A - B) / B × 100%

A = 實際單價（本次購買）
B = Anchor 基準價
```

---

## 📐 Buffer Zone 判定（分層閾值）

### 包裝食品（supermarket / discount）

| 評級 | 條件 | Alert Level |
|------|------|-------------|
| 🟢 買得好平 | D < -15% | `good_deal` |
| ⚪ 合理市價 | -15% ≤ D ≤ +12% | `reasonable`（靜音）|
| 🟡 略高於市價 | +12% < D ≤ +35% | `slightly_high` |
| 🔴 買貴咗 | +35% < D ≤ +150% | `price_spike` |
| ⚠️ 數據異常 | D > +150% | `data_anomaly` |

### 街市生鮮（wet_market，含 is_fresh_food=true）

| 評級 | 條件 | Alert Level |
|------|------|-------------|
| 🟢 買得好平 | D < -20% | `good_deal` |
| ⚪ 合理市價 | -20% ≤ D ≤ +20% | `reasonable`（靜音）|
| 🟡 略高於市價 | +20% < D ≤ +40% | `slightly_high` |
| 🔴 買貴咗 | +40% < D ≤ +150% | `price_spike` |
| ⚠️ 數據異常 | D > +150% | `data_anomaly` |

---

## 🗄️ 數據庫 Schema（Stage 1-4 新增/修改）

### receipt_items（Stage 1 新增欄位）

| Column | Type | Description |
|--------|------|-------------|
| `normalized_unit_price` | DECIMAL(12,4) | **標準化單價**（每標準單位），所有比較以此為準 |
| `standard_name` | TEXT | LLM 生成的標準化名稱（如「牛肉片」「菜心」）|
| `is_fresh_food` | BOOLEAN | true = 生鮮（蔬菜/肉類/魚），緩衝區更闊 |
| `confidence_score` | DECIMAL(3,2) | LLM 解析信心度，< 0.5 的項目不參與跨家庭聚合 |

### price_history（Stage 2 新增欄位）

| Column | Type | Description |
|--------|------|-------------|
| `freshness_weight` | DECIMAL(3,2) | 時間衰減權重（今日 1.0，三日前 0.1）|
| `price_per_kg` | DECIMAL(12,4) | 每公斤單價（用於跨商品比較）|
| `price_per_pcs` | DECIMAL(12,4) | 每件/每盒單價 |
| `days_ago` | INT | 快取：記錄日期距離今天的天數 |

### afcd_wholesale_prices（Stage 2 新增）

| Column | Type | Description |
|--------|------|-------------|
| `category` | TEXT | 蔬菜 / 淡水魚 / 海水魚 |
| `item_name` | TEXT | 如「菜心」「黃鱔」|
| `wholesale_price` | DECIMAL | 每日批發價 |
| `unit` | TEXT | 斤 / 両 / 公斤 |
| `retail_multiplier` | DECIMAL | 預設 2.0（批發價 × 倍 = 零售估算）|

### district_price_index（Stage 2 新增）

| Column | Type | Description |
|--------|------|-------------|
| `district` | TEXT | 如「中西區」「元朗」|
| `category` | TEXT | 超市 / 街市 / all |
| `index_coefficient` | DECIMAL | 1.0 = 基準，>1.0 = 更貴（如中西區 1.2）|

### household_trust_scores（Stage 3 新增）

| Column | Type | Description |
|--------|------|-------------|
| `trust_score` | DECIMAL(3,2) | 0.0-1.0，< 0.3 排除於跨家庭平均 |
| `total_entries` | INT | 總輸入次數 |
| `correct_entries` | INT | 被認定準確的次數 |

### community_badges（Stage 4 新增）

| Column | Type | Description |
|--------|------|-------------|
| `badge_type` | TEXT | `smart_eye_weekly` |
| `district` | TEXT | 如「將軍澳區」|
| `percentile_rank` | DECIMAL | 5.0 = 前 5% |
| `savings_vs_district` | DECIMAL | 估算慳幾多錢 |

### product_standard_names（Stage 3 新增）

| Column | Type | Description |
|--------|------|-------------|
| `standard_name` | TEXT | LLM 標準化名稱（唯一）|
| `master_product_id` | UUID | 對應的 master_products |
| `match_count` | INT | 累計使用次數 |
| `confidence_score` | DECIMAL | 準確率 |

---

## 🌍 地理分層（Geo Clustering）

### 三層優先級

| 層 | 範圍 | 精度 |
|---|---|---|
| **同街市 1.5km** | Haversine 半徑內所有商店 | 最高（考慮實際購物地點）|
| **同區** | 同一個 district | 中等 |
| **跨區** | 全港 + district_index 修正 | 最低（需修正系數）|

### district_index 修正公式
```
cross_district_price = raw_price / district_index
例如：中西區 index=1.2，原始價 $12 → 基準線 $10
```

---

## 🔒 隱私保護（Privacy Shield）

**鐵規：** 所有跨家庭數據輸出必須係聚合形式，絕不暴露個人資訊。

```
✅ 可顯示：「太和街市 14 位用戶的平均菜心價 $12/斤」
❌ 不可顯示：「天晉三期 20 樓 B 室買咗菜心 $14」
```

**最低門檻：**
- 至少 5 個不同家庭
- 至少 10 個數據點
- 信任分 trust_score ≥ 0.3
- confidence_score ≥ 0.5

---

## 🤝 渠道鐵律（Store-Type Tagging）

**不同渠道的數據不可以直接比較：**

| 渠道 | Tag | 比較範圍 |
|---|---|---|
| 奢華超市 | `high_end` | City'super, Marks & Spencer, Oliver's |
| 大眾超市 | `supermarket` | 百佳、惠康、U購 Select、DON DON DONKI |
| 折扣/急凍 | `discount` | 大生、佳寶、759阿信屋 |
| 傳統街市 | `wet_market` | 食環署街市、領展街市 |

**鐵律：** `wet_market` 只跟 `wet_market` 比，`supermarket` 只跟 `supermarket` 比。

---

## ⏰ 時間衰減（Freshness Decay）

用於 Layer 2 自家歷史加權計算：

| days_ago | weight |
|---|---|
| 0（今日）| 1.0 |
| 1（昨日）| 0.7 |
| 2（前日）| 0.3 |
| ≥ 3 | 0.1 |

---

## 🎮 精明眼勳章（Community Badge）

**條件：**
- 整週開支比同區平均低 >15%
- 至少 10 種不同物品（種類均衡）
- 單一類別不超過 70%
- 至少 5 次不同購物行程

**訊息格式：**
> 🎉 恭喜！姐姐本週躋身【將軍澳區街市精明眼】前 5%，幫你慳咗約 $240！

---

## 📝 修改記錄

| 日期 | 修改內容 |
|------|---------|
| 2026-06-24 | Stage 1-4 完成：LLM normalization、四層 Anchor、Buffer Zone、跨家庭、Geo Clustering、精明眼勳章 |
