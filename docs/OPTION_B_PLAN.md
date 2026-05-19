# Option B Plan: Complete Price Workflow

## 目標
修復以下空 table 的寫入 flow：
- `price_history` — 每次記帳後寫入
- `product_aliases` — 產品多語言別名
- `shop_aliases` / `shops` — 店舖 matching
- `price_alerts` — 價格警報（需 trigger edge function）
- `expense_summaries` — 月度支出彙總

---

## Phase 1: 確保 Items 正常寫入

### 問題根因
LLM 返回 `items[0].unit_price = null`，導致 `_buildItemsFromIntent` 算出 `line_total = null`，最終 `price_history` 無法寫入。

### 修復
1. **chat-parser**: 修復 amount extraction — `$40` 要正确解析為 `40`
2. **Flutter `_buildItemsFromIntent`**: 當 LLM 返回 `unit_price: null`，fallback 到 `intent.amount`
3. 測試：`"Pulang snapper, 40$, jin"` → `items: [{item_name: "紅衫魚", unit_price: 40}]`

---

## Phase 2: Shop Matching Flow

### 問題根因
`shop_matching_service` 在 chat_screen 未被调用，`shops` / `shop_aliases` 表全空。

### 修復
在 `_onConfirm` 中：
1. 從 `intent.storeName` 或從 `intent.rawText` 推斷 store name
2. Call `ShopMatchingService.matchShop()` → 得到 `shopId`
3. 寫入 `receipts.shop_id`
4. 更新 `price_history` 的 `shop_id`

---

## Phase 3: Price History Write

### 問題根因
`_writePriceHistory` 雖然存在，但 `items` 可能全為 `unit_price: null`，導致 skip。

### 修復
1. 確保 `receipt_items` 寫入成功（Phase 1）
2. `_writePriceHistory` 改為從 `receipt_items` 讀取真實數據（唔係從 intent.items）
3. 寫入 `price_history`：master_product_id, shop_id, location, price, unit, source_receipt_id

---

## Phase 4: Product Aliases + Master Products

### 問題根因
`product_matching_service` 未被 chat flow 调用，導致 `product_aliases` 表全空。

### 修復
1. 在 `_writePriceHistory` 完成後，調用 `ProductMatchingService.upsertFromReceiptItem()`
2. 對於每個 receipt_item：match 或 create master_product + aliases
3. 支援多語言（菲仲文/印尼文/英文 → 標準中文名）

---

## Phase 5: Expense Summaries

### 問題根因
無寫入機制。

### 修復
1. 在每次 receipt insert 完成後，upsert `expense_summaries`
2. 按 employer_id + month + prd_cate 聚合
3. 記錄：total_amount, transaction_count, avg_price

---

## Phase 6: Price Alert Engine Trigger

### 問題根因
`price-alert-engine` edge function 未被調用。

### 修復
1. 在 `_writePriceHistory` 完成後，call `price-alert-engine` edge function
2. 傳入：employer_id, master_product_id, shop_id, new_price, unit
3. Edge function 内部：
   - 計算基線（last price 或 7-day rolling avg）
   - 超過 threshold（15%）→ insert `price_alerts`
   - 檢查 weather suppression

---

## Phase 7: Cleanup — 移除無效 Schema

### 問題根因
docs 提到 `price_data` table 但實際不存在，`price_alerts` schema 跟 implementation 不匹配。

### 修復
1. 清理 `CROWDSOURCED_PRICE_SYSTEM.md` — 移除 `price_data`（不存在）
2. 確認 `price_alerts` / `price_alert_suppression` schema 跟 edge function 一致
3. 更新 `ARCHITECTURE.md` 的 schema summary

---

## Execution Order

```
Phase 1 (items) → Phase 2 (shop) → Phase 3 (price history) →
Phase 4 (product aliases) → Phase 5 (expense summaries) →
Phase 6 (alert engine) → Phase 7 (cleanup)
```

每個 Phase 单独 commit，方便 review。

---

## 預期結果

| Table | 修復前 | 修復後 |
|-------|--------|--------|
| `receipt_items` | 有 record 但 unit_price=null | 有 record 且 unit_price=40 |
| `price_history` | 空 | 每次記帳寫入 |
| `product_aliases` | 空 | 每次記帳 upsert |
| `shops` | 空 | shop matching 時創建 |
| `shop_aliases` | 空 | shop matching 時創建 |
| `price_alerts` | 空 | 價格超標時創建 |
| `expense_summaries` | 空 | 每月聚合 |

---

## 風險與注意事項

1. **LLM 仍可能 parse 錯** — Phase 1 係最大變數，取決於 LLM 解析準確度
2. **Shop matching 依賴 store_name** — 如果 intent.storeName 為 null，效果有限
3. **Price alert threshold** — 目前假設 15%，可視為 configurable
4. **expense_summaries monthly aggregation** — 需要 periodic cron job 或 trigger