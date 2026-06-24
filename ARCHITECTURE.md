# MaidLedger — Architecture & Workflow Documentation

**用途：** 維護參考 — 快速定位 logic 修改位置
**最後更新：** 2026-06-24

---

## 🗺️ Component → Path 對照表

| 組件 | 路徑 | 用途 |
|---|---|---|
| **Chat flow (主力)** | `supabase/functions/chat-orchestrate/index.ts` | 接收文字 → 解析 → 寫入 receipt（支援 attached_image_base64） |
| **Receipt scan flow** | `supabase/functions/receipt-orchestrate/index.ts` | lock → patch → RPC 協調 |
| **Receipt vision** | `supabase/functions/receipt-vision/index.ts` | 純 LLM Vision 解析（qwen3-vl-30b） |
| **Receipt parse** | `supabase/functions/receipt-parse/index.ts` | OCR 解析 receipt |
| **Receipt write** | `supabase/functions/receipt-writer/index.ts` | 寫入 DB（含 createFromChat 圖片上傳） |
| **Shop matching** | `supabase/functions/shop-manager/index.ts` | canonical name + matching |
| **Product matching** | `supabase/functions/product-manager/index.ts` | master product + brand |
| **Price alert engine** | `supabase/functions/price-alert-engine/index.ts` | 價格警報 + 分層 Buffer Zone + 人性化文案 |
| **Price reference engine** | `supabase/functions/price-reference-engine/index.ts` | 四層 Anchor 查詢（geo/CC/歷史/AFCD） |
| **Cross-household query** | `supabase/functions/cross-household-query/index.ts` | 匿名化跨家庭聚合價格 |
| **Geo price cluster** | `supabase/functions/geo-price-cluster/index.ts` | 地理範圍 1.5km 聚合價格 |
| **AFCD price fetcher** | `supabase/functions/afcd-price-fetcher/index.ts` | 政府批發價每日拉取 |
| **Community badge check** | `supabase/functions/community-badge-check/index.ts` | 精明眼勳章每週評估 |
| **Notification broadcast** | `supabase/functions/notification-broadcast/index.ts` | 通知僱主 |
| **Daily summary** | `supabase/functions/daily-summary/index.ts` | 分享按鈕每日摘要（按 transaction_date） |
| **Helper App** | `apps/helper_app/lib/` | 工人所有畫面 |
| Chat Screen | `apps/helper_app/lib/features/chat/chat_screen.dart` | 價錢入帳 |
| History Screen | `apps/helper_app/lib/features/history/history_screen.dart` | 歷史查詢 |
| Scan Screen | `apps/helper_app/lib/features/scan/scan_screen.dart` | 掃描收據 |
| **Employer App** | `apps/employer_app/lib/` | 僱主所有畫面 |
| **Scraper** | `services/scraper/src/scraper.py` | Python 爬蟲（HKTVmall / 惠康 / 百佳） |
| **DB Schema ERD** | `docs/SCHEMA.html` | 實體關係圖（不斷更新） |
| **Migrations** | `supabase/migrations/` | SQL schema 變更 |

---

## 🗄️ Core Database Tables

| Table | 用途 |
|---|---|
| `receipts` | 收據 header（employer_id, helper_id, total, transaction_date, raw_text, date_anomaly） |
| `receipt_items` | 收據項目（receipt_id, item_name, extracted_brand/name/spec, unit_price, qty, prd_cate, standard_name, normalized_unit_price, is_fresh_food, confidence_score） |
| `shops` | 商戶標準化（canonical_name, shop_type, region, latitude, longitude） |
| `shop_aliases` | 商戶別名 → shops（raw_name → canonical） |
| `master_products` | 商品主數據（canonical_name, brand, prd_cate, search_keywords） |
| `product_aliases` | 商品別名 → master_products（raw_name → canonical） |
| `price_history` | 價格歷史（master_product_id, shop_id, price, unit, source_type, freshness_weight, price_per_kg, price_per_pcs） |
| `user_profiles` | 用戶（employer/helper，name, phone, short_code） |
| `cc_prices` | 消委會物價通（每日更新，name_zh/en, brand, prices JSON, price_per_100g） |
| `afcd_wholesale_prices` | AFCD 每日批發價（蔬菜/淡水魚/海水魚，retail_multiplier） |
| `district_price_index` | 地區物價修正系數（district × category × month） |
| `household_trust_scores` | 家庭信任分（trust_score, total_entries, correct_entries） |
| `price_alert_config` | 用戶自定義 alert threshold（per category） |
| `community_badges` | 精明眼勳章（badge_type, district, percentile_rank, savings_vs_district） |
| `product_standard_names` | LLM standard_name → master_product_id 映射（match_count, confidence_score） |
| `employer_helper_relations` | 僱主-工人關係（employer_id, helper_id, status） |
| `employer_payments` | 付款記錄（滾動結餘：收入 − 支出，created_by 記錄操作者） |
| `store_categories` / `prd_categories` | 分類主數據 |
| `chat_logs` | LLM 調用審計 |

---

## 🔄 Workflow 總覽

### Chat Flow（Helper App → chat-orchestrate）
```
用戶輸入文字 + 可選相片 → chat-orchestrate → LLM 文字解析
    │
    ├─ image_picker (gallery/camera) → base64
    │
    ├─ EXIF GPS 讀取 → district/region → location hint
    │
    ↓
rate limit check（1分鐘 >6次 → 限速；2分鐘 >5次 non-expense → 封30分鐘）
    ↓
buildResponse(intent)
    ↓
confidence>0.7 + 有金額 → _showSaveDialog()
    ↓
INSERT receipts (parse_status="parsed") + receipt_items
    │
    └─ DB Trigger: 只對 parse_status="pending" 觸發 receipt-orchestrate
    │         （chat flow 係 "parsed"，唔會重新走 vision）
    ↓
notification-broadcast（非阻塞）
```

### OCR Scan Flow（Helper App → receipt-orchestrate）
```
Camera Capture → ML Kit OCR（壓縮 ~500KB）→ receipt-orchestrate
    ↓
Atomic Lock（parse_status: pending → processing）
    ↓
LLM Vision Parse（qwen3-vl-30b via OpenRouter）
    ↓
UPDATE receipts（parsed_data + parse_status: parsed）
    ↓
Shop matching（Step 3b，早於 product matching）
    ↓
INSERT receipt_items（batch）
    ↓
Product matching + price_history（per item，獨立 try/catch）
    ↓
Realtime notification → Employer App
```

### My Code Flow（Employer App）
```
user_profiles.short_code → Display（6位邀請碼，如 HE5KZV）
    ↓
Worker 輸入 short_code → RelationService.linkToEmployer()
    ↓
INSERT / UPDATE employer_helper_relations（status='active'）
```

---

## 🌏 Critical Technical Rules

### 🛡️ Anti-Cheat Rules（防作弊）

| 規則 | 條件 | 結果 |
|---|---|---|
| **Rule 1** | `transaction_date` > 3 天前 | `needs_review = true` |
| **Rule 2** | 3 日內，同一 `store_cate` + 同一 `amount` + **所有 items 完全相同** | `needs_review = true` |

- **適用範圍：** Chat 和 Scan 兩條 path 統一規則
- **Helper 行為：** 可以保存，但 receipt 標記為 `needs_review = true`
- **返回：** `similar_receipts[]` 陣列，包含相似記錄供僱主對比
- **實作位置：** `receipt-writer` 的 `checkAntiCheat()` 函數

- **Timezone:** `Asia/Hong_Kong`，`toLocaleString("en-US", {timeZone: "Asia/Hong_Kong"})`
- **Auth:** Edge Functions 内部調用用 `SUPABASE_SERVICE_ROLE_KEY`（唔係 ANON_KEY）
- **LLM Provider:** OpenRouter（DeepSeek V4 / GPT-4o）
- **OCR:** Google ML Kit（client-side，Flutter 端側）
- **Vision Model:** `qwen/qwen3-vl-30b-a3b-instruct`（性價比最高，~$0.13/M tokens）
- **PostgREST ILIKE Bug:** receipt-writer 用 in-memory matching 绕过 URL-encoding 問題
- **Race Condition:** receipt-orchestrate 用 Atomic Lock（UPDATE parse_status WHERE pending）防止雙重處理

---


## 💰 Price Anchor System

### 四層 Anchor Priority

| Layer | 名稱 | 數據來源 | 信心度 |
|---|---|---|---|
| Layer 0 | Geo Cluster | 同街市 1.5km 內其他家庭（48h） | 最高 |
| Layer 1 | 消委會中位數 | Consumer Council 超市物價通 | 85% |
| Layer 2 | 自家歷史 | 45天 trimmed mean（freshness weighted） | 70% |
| Layer 3 | AFCD 批發價 | 政府批發價 × 1.8-2.2 倍 | 50% |

### Buffer Zone（統一公式 D = (A-B)/B × 100%）

| 類型 | 🟢 好平 | ⚪ 合理（靜音） | 🟡 略高 | 🔴 買貴 | ⚠️ 異常 |
|---|---|---|---|---|---|
| 包裝食品 | D < -15% | -15% ≤ D ≤ +12% | +12% < D ≤ +35% | D > +35% | D > +150% |
| 街市生鮮 | D < -20% | -20% ≤ D ≤ +20% | +20% < D ≤ +40% | D > +40% | D > +150% |

### 渠道鐵律
wet_market 只跟 wet_market 比，supermarket 只跟 supermarket 比

---

## 📁 Edge Functions API

| Function | Input | Output |
|---|---|
| `chat-orchestrate` | `{text, user_id, location?, attached_image_base64?}` | `{success, receipt_id, needs_review}` |
| `receipt-orchestrate` | `{receipt_id}`（webhook/cron） | `{success}` |
| `receipt-parse` | `{image_base64?, image_url?}` | `{success, items, standard_name, normalized_unit_price...}` |
| `receipt-writer` | `{receipt_data}` | `{receipt_id}` |
| `shop-manager` | `{store_name, location?}` | `{shop_id, canonical_name}` |
| `product-manager` | `{item_name, brand?}` | `{product_id, canonical_name}` |
| `notification-broadcast` | `{user_id, message}` | `{sent}` |
| `daily-summary` | (none) | `{success, text}` |
| `price-reference-engine` | `{standard_name, lat?, lng?, district?, store_type?}` | `{anchor_price, anchor_type, confidence}` |
| `price-alert-engine` | `{receipt_id, user_id}` | `{alerts_created, alerts[]}` |
| `cross-household-query` | `{standard_name, district?, store_type?}` | `{aggregated: {median, avg, count}}` |
| `geo-price-cluster` | `{lat, lng, standard_name}` | `{aggregated: {median, count}, shops_in_radius}` |
| `afcd-price-fetcher` | (cron/manual) | `{total_upserted, errors}` |
| `community-badge-check` | `{employer_id, district}` | `{eligible, message, savings_vs_district}` |

---

---

## 🏷️ 相關文檔

- **Crowdsourced Price System:** [docs/CROWDSOURCED_PRICE_SYSTEM.md](./docs/CROWDSOURCED_PRICE_SYSTEM.md)
- **DB Schema ERD:** [docs/SCHEMA.html](./docs/SCHEMA.html)
- **待修問題追蹤:** [TODO.md](./TODO.md)