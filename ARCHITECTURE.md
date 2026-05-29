# MaidLedger — Architecture & Workflow Documentation

**用途：** 維護參考 — 快速定位 logic 修改位置
**最後更新：** 2026-05-29

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
| **Price alert engine** | `supabase/functions/price-alert-engine/index.ts` | 價格警報 + weather suppression |
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
| `receipt_items` | 收據項目（receipt_id, item_name, extracted_brand/name/spec, unit_price, qty, prd_cate） |
| `shops` | 商戶標準化（canonical_name, shop_type, region） |
| `shop_aliases` | 商戶別名 → shops（raw_name → canonical） |
| `master_products` | 商品主數據（canonical_name, brand, prd_cate, search_keywords） |
| `product_aliases` | 商品別名 → master_products（raw_name → canonical） |
| `price_history` | 價格歷史（master_product_id, shop_id, price, unit, source_type） |
| `user_profiles` | 用戶（employer/helper，name, phone, short_code） |
| `employer_helper_relations` | 僱主-工人關係（employer_id, helper_id, status） |
| `employer_payments` | 付款記錄（滾動結餘：收入 − 支出，created_by 記錄操作者） |
| `store_categories` / `prd_categories` | 分類主數據 |
| `chat_logs` | LLM 調用審計 |

---

## 🔄 Workflow 總覽

### Chat Flow（Helper App → chat-orchestrate）
```
用戶輸入文字 → chat-orchestrate → LLM 解析（is_expense?）
    ↓
rate limit check（1分鐘 >6次 → 限速；2分鐘 >5次 non-expense → 封30分鐘）
    ↓
buildResponse(intent)
    ↓
confidence>0.7 + 有金額 → _showSaveDialog()
    ↓
INSERT receipts + receipt_items
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

- **Timezone:** `Asia/Hong_Kong`，`toLocaleString("en-US", {timeZone: "Asia/Hong_Kong"})`
- **Auth:** Edge Functions 内部調用用 `SUPABASE_SERVICE_ROLE_KEY`（唔係 ANON_KEY）
- **LLM Provider:** OpenRouter（DeepSeek V4 / GPT-4o）
- **OCR:** Google ML Kit（client-side，Flutter 端側）
- **Vision Model:** `qwen/qwen3-vl-30b-a3b-instruct`（性價比最高，~$0.13/M tokens）
- **PostgREST ILIKE Bug:** receipt-writer 用 in-memory matching 绕过 URL-encoding 問題
- **Race Condition:** receipt-orchestrate 用 Atomic Lock（UPDATE parse_status WHERE pending）防止雙重處理

---

## 📁 Edge Functions API

| Function | Input | Output |
|---|---|---|
| `chat-orchestrate` | `{text, user_id, location?, attached_image_base64?}` | `{success, receipt_id, needs_review, errors}` |
| `receipt-orchestrate` | `{receipt_id}`（webhook trigger）或 cron fallback | `{success}` |
| `receipt-parse` | `{image_base64?, image_url?}` | `{success, items, total}` |
| `receipt-writer` | `{receipt_data}` | `{receipt_id}` |
| `shop-manager` | `{store_name, location?}` | `{shop_id, canonical_name}` |
| `product-manager` | `{item_name, brand?}` | `{product_id, canonical_name}` |
| `notification-broadcast` | `{user_id, message}` | `{sent}` |
| `daily-summary` | (none, uses auth) | `{success, text}`（每日採購摘要） |

---

## 🏷️ 相關文檔

- **Crowdsourced Price System:** [docs/CROWDSOURCED_PRICE_SYSTEM.md](./docs/CROWDSOURCED_PRICE_SYSTEM.md)
- **DB Schema ERD:** [docs/SCHEMA.html](./docs/SCHEMA.html)
- **待修問題追蹤:** [TODO.md](./TODO.md)