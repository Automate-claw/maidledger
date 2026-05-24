# MaidLedger 架構文檔

> ⚠️ **規矩**：每次修改架構（新增/移動/刪除 component）後，必須立即更新此文檔。
> 此文檔係 Developer Agent 工作指引 — 搵唔到嘢時第一時間睇呢份。

---

## 🗺️ 整體架構圖

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           CLIENTS                                        │
│   ┌─────────────────────┐          ┌──────────────────────┐             │
│   │   employer_app      │          │     helper_app       │             │
│   │   (Flutter /僱主)   │          │   (Flutter /工人)    │             │
│   └─────────────────────┘          └──────────────────────┘             │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                     SUPABASE (Backend-as-a-Service)                      │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                     EDGE FUNCTIONS                                │    │
│  │   (Deno / TypeScript, 部署喺 Supabase Cloud)                      │    │
│  │                                                                  │    │
│  │  ┌───────────-──┐  ┌───────────────┐  ┌──────────────────┐     │    │
│  │  │ chat-       │  │ receipt-      │  │ product-         │     │    │
│  │  │ orchestrate │→ │ orchestrate   │→ │ manager          │     │    │
│  │  │ ⭐ 主力     │  │ (coordination)│  │                  │     │    │
│  │  └──────────────┘  └───────────────┘  └──────────────────┘     │    │
│  │                                                                  │    │
│  │  ┌───────────-──┐  ┌───────────────┐  ┌──────────────────┐     │    │
│  │  │ receipt-     │  │ receipt-      │  │ shop-            │     │    │
│  │  │ parse        │  │ writer        │  │ manager          │     │    │
│  │  │ (new, HTTP)  │  │               │  │                  │     │    │
│  │  └──────────────┘  └───────────────┘  └──────────────────┘     │    │
│  │                                                                  │    │
│  │  ┌───────────-──┐  ┌───────────────┐  ┌──────────────────┐     │    │
│  │  │ chat-parser  │  │ receipt-      │  │ price-alert-     │     │    │
│  │  │ (legacy)     │  │ parser (old)   │  │ engine           │     │    │
│  │  └──────────────┘  └───────────────┘  └──────────────────┘     │    │
│  │                                                                  │    │
│  │  ┌───────────-──┐  ┌───────────────┐                            │    │
│  │  │ notification │  │ weather-check │                            │    │
│  │  │ -broadcast  │  │               │                            │    │
│  │  └──────────────┘  └───────────────┘                            │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │               POSTGRESQL (via PostgREST auto-CRUD)              │    │
│  │                                                                  │    │
│  │  Tables: receipts, receipt_items, master_products,              │    │
│  │          product_aliases, shops, price_history,                 │    │
│  │          employer_helper_relations, user_profiles,              │    │
│  │          expense_summaries, employer_payments,                  │    │
│  │          store_categories, prd_categories, chat_logs,            │    │
│  │          price_data, price_alerts                                │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │               STORAGE (File Bucket)                              │    │
│  │  receipt-images/ — 收據截圖存放                                  │    │
│  └─────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘

        │
        ▼

┌──────────────────────────────────┐
│  SCRAPER (Python + Playwright)   │
│  services/scraper/src/scraper.py │
│  定時爬蟲，更新 price_data 表     │
└──────────────────────────────────┘
```

---

## 📁 完整資料夾結構

```
maidledger/
├── apps/
│   ├── employer_app/              # 僱主 Flutter App
│   │   └── lib/
│   │       ├── main.dart
│   │       ├── core/
│   │       │   └── services/
│   │       │       └── supabase_client_provider.dart
│   │       ├── features/
│   │       │   ├── auth/
│   │       │   │   ├── auth_provider.dart
│   │       │   │   └── login_screen.dart
│   │       │   ├── mycode/
│   │       │   │   └── my_code_screen.dart
│   │       │   ├── receipts/
│   │       │   │   └── receipts_screen.dart
│   │       │   └── settings/
│   │       │       └── settings_screen.dart
│   │       ├── providers/
│   │       ├── screens/
│   │       └── widgets/
│   │
│   └── helper_app/                # 工人 Flutter App
│       └── lib/
│           ├── main.dart
│           ├── core/services/
│           │   ├── ai_booking_agent_service.dart  ⚠️ API key hardcoded
│           │   ├── location_service.dart
│           │   ├── product_matching_service.dart
│           │   ├── receipt_scanner_provider.dart
│           │   ├── receipt_scanner_service.dart
│           │   ├── relation_service.dart
│           │   ├── shop_matching_service.dart
│           │   └── supabase_client_provider.dart
│           └── features/
│               ├── auth/
│               │   ├── auth_provider.dart
│               │   ├── login_screen.dart
│               │   └── relation_gate.dart
│               ├── chat/
│               │   └── chat_screen.dart           ⚠️ price_history 寫兩次
│               ├── history/
│               │   ├── history_screen.dart
│               │   ├── receipt_detail_screen.dart
│               │   └── record_payment_screen.dart
│               ├── scan/
│               │   └── scan_screen.dart
│               └── settings/
│                   └── settings_screen.dart
│
├── supabase/
│   ├── functions/                # ⭐ 主要後端邏輯（所有 Edge Functions）
│   │   ├── chat-orchestrate/     # ⭐ 主力整合點（302 lines）
│   │   │   └── index.ts
│   │   ├── receipt-orchestrate/  # 多步驟協調（334 lines）
│   │   ├── receipt-writer/      # 寫入 receipts（354 lines）
│   │   ├── receipt-parse/       # 新版 receipt 解析（189 lines）
│   │   ├── shop-manager/        # 商戶 matching（321 lines）
│   │   ├── product-manager/      # 商品 master data（250 lines）
│   │   ├── chat-parser/         # 舊版 chat 解析（520 lines, legacy）
│   │   ├── receipt-parser/       # 舊版 receipt 解析（283 lines, old）
│   │   ├── price-alert-engine/  # 價格警報（143 lines）
│   │   ├── notification-broadcast/  # 通知廣播（123 lines）
│   │   └── weather-check/        # 天氣檢查（75 lines）
│   │
│   └── migrations/               # SQL migrations
│       ├── 002_full_schema.sql
│       ├── 003_receipt_items.sql
│       ├── 004_categories.sql
│       ├── 010_chat_logs.sql
│       └── 012_master_products_and_aliases.sql
│
├── services/
│   └── scraper/                  # Python 爬蟲
│       └── src/
│           └── scraper.py        # Playwright crawler for HKTVmall/Wellcome/ParknShop
│
├── packages/
│   ├── receipt-parser/           # Dart package (唔活躍)
│   ├── localization/            # Dart package (唔活躍)
│   └── archive/                 # 棄用 code
│       ├── ai-booking-agent/
│       ├── price-alert-engine/
│       └── receipt-scanner/
│
└── docs/
    ├── SCHEMA.html              # 數據庫 ERD 圖（手動更新）
    ├── ARCHITECTURE.md          # 本文件
    └── *.md                     # 其他設計文檔
```

---

## 🎯 Component → 路徑 對照表（最高使用頻率）

| 組件 | 路徑 | 重點 |
|---|---|---|
| **Chat flow (主力)** | `supabase/functions/chat-orchestrate/index.ts` | 接收文字 → 解析 → 寫入 receipt |
| **Receipt scan flow** | `supabase/functions/receipt-orchestrate/index.ts` | lock → patch → RPC 協調 |
| **Receipt parse** | `supabase/functions/receipt-parse/index.ts` | OCR 解析 receipt |
| **Receipt write** | `supabase/functions/receipt-writer/index.ts` | 寫入 DB |
| **Shop matching** | `supabase/functions/shop-manager/index.ts` | canonical name + matching |
| **Product matching** | `supabase/functions/product-manager/index.ts` | master product + brand |
| **Helper App** | `apps/helper_app/lib/` | 工人所有畫面 |
| **Chat Screen** | `apps/helper_app/lib/features/chat/chat_screen.dart` | 價錢入帳 |
| **History Screen** | `apps/helper_app/lib/features/history/history_screen.dart` | 歷史查詢 |
| **Scan Screen** | `apps/helper_app/lib/features/scan/scan_screen.dart` | 掃描收據 |
| **Employer App** | `apps/employer_app/lib/` | 僱主所有畫面 |
| **Scraper** | `services/scraper/src/scraper.py` | Python 爬蟲 |
| **DB Schema** | `docs/SCHEMA.html` | ERD 圖 |
| **Migrations** | `supabase/migrations/` | SQL schema 變更 |

---

## 🔌 Edge Functions API 對照

| Function | HTTP Method | Input | Output | 用途 |
|---|---|---|---|---|
| `chat-orchestrate` | POST | `{text, user_id, location?}` | `{success, receipt_id, needs_review, errors}` | 主力 chat flow |
| `receipt-orchestrate` | POST | `{receipt_id, ...}` | `{success, ...}` | receipt 多步協調 |
| `receipt-parse` | POST | `{image_base64?, image_url?}` | `{success, items, total}` | OCR 解析 |
| `receipt-writer` | POST | `{receipt_data}` | `{receipt_id, ...}` | 寫入 receipt |
| `shop-manager` | POST | `{store_name, location?}` | `{shop_id, canonical_name, ...}` | 商戶 matching |
| `product-manager` | POST | `{item_name, brand?}` | `{product_id, canonical_name, ...}` | 商品 matching |
| `chat-parser` | POST | `{text, user_id}` | `{items, total, store_name?}` | 舊版 chat 解析 |
| `receipt-parser` | POST | `{image_base64}` | `{items, total}` | 舊版 receipt |
| `price-alert-engine` | — | cron triggered | — | 價格警報 |
| `weather-check` | — | cron triggered | — | 天氣檢查 |
| `notification-broadcast` | POST | `{user_id, message}` | `{sent}` | 通知 |

---

## 🗄️ 主要資料庫 Tables

| Table | 用途 | Key Fields |
|---|---|---|
| `user_profiles` | 用戶（employer/helper） | id, role, name, phone |
| `employer_helper_relations` | 僱主-工人關係 | employer_id, helper_id, status |
| `receipts` | 收據 header | id, employer_id, helper_id, relation_id, total, transaction_date |
| `receipt_items` | 收據項目（新版） | receipt_id, item_name, price, quantity, unit |
| `shops` | 商戶 | id, name, canonical_name, district, region |
| `master_products` | 商品主數據 | id, canonical_name, brand, prd_cate, default_unit |
| `product_aliases` | 商品別名 | id, raw_name, master_product_id |
| `price_history` | 價格歷史 | shop_id, master_product_id, price, recorded_at |
| `expense_summaries` | 費用摘要 | employer_id, helper_id, month, total |
| `employer_payments` | 付款記錄 | employer_id, helper_id, amount, paid_at |
| `store_categories` | 商戶分類 | code, name_tc |
| `prd_categories` | 商品分類 | code, name_tc |
| `price_data` | 爬蟲價格數據 | supermarket, category, product_name, price |
| `chat_logs` | chat 歷史 | user_id, input_text, output_response |

---

## ⚠️ 已知問題（待修）

| # | 位置 | 問題 | 嚴重 |
|---|---|---|---|
| 1 | `apps/helper_app/lib/core/services/product_matching_service.dart` | `createMasterProduct` 雙重 canonicalName 導致編譯失敗 | 🔴 |
| 2 | `apps/helper_app/lib/core/services/ai_booking_agent_service.dart` | API key hardcoded | 🔴 |
| 3 | `apps/helper_app/lib/features/chat/chat_screen.dart` | `_saveExpense` 中 `price_history` 寫兩次 | 🔴 |
| 4 | `supabase/functions/shop-manager/index.ts` | `textSearch` 無 catch，可能 crash | 🟡 |
| 5 | `receipt-orchestrate` | `timeout` 判斷太闊，race condition | 🟡 |
| 6 | `_buildItemsFromIntent` | 只取第一個 price（應取最大） | 🟡 |

---

## 🛠️ 常用指令

```bash
# 切換 branch
git checkout dev && git pull
git checkout -b feature/<name>

# 部署 Edge Function
supabase functions deploy <function-name>

# 本地測試 Edge Function
supabase functions serve <function-name> --env-file .env.local

# Flutter build
cd apps/employer_app && flutter build apk --release
cd apps/helper_app && flutter build apk --release

# Git push
git add . && git commit -m "<type>(<scope>): <subject>"
git push --set-upstream origin $(git branch --show-current)

# Supabase migration
supabase db push
```

---

## 🌏 重要技術細節

- **HK Timezone**: 所有日期用 `Asia/Hong_Kong`，`toLocaleString("en-US", {timeZone: "Asia/Hong_Kong"})`
- **PostgREST ILIKE Bug**: `receipt-writer` 用 in-memory matching 绕过 PostgREST URL-encoding 問題
- **Race Condition**: receipt-orchestrate 的 lock → PATCH → RPC 流程可能有同步問題
- **Edge Function Auth**: 用 `SUPABASE_SERVICE_ROLE_KEY`（唔係 ANON_KEY）做 backend-internal calls
- **LLM Provider**: OpenRouter (DeepSeek V4 / GPT-4o)
- **OCR**: Google ML Kit (client-side Flutter)

---

## 🔄 開發流程

```
1. 從 dev branch 開新 feature branch
   git checkout dev && git pull && git checkout -b feature/<name>

2. 開發 + 測試

3. Commit + Push
   git add . && git commit -m "feat(<scope>): description"
   git push --set-upstream origin feature/<name>

4. Merge to dev（需要 PR review）

5. 發布：dev → master（需要 Joe 確認）
```

---

## 📝 更新日誌

| 日期 | 更新内容 |
|---|---|
| 2026-05-24 | 初始架構文檔建立，含完整 folder structure、API 對照、DB tables、已知問題、常用指令 |

---

*最後更新：2026-05-24 14:30 GMT+8*