# MaidLedger MVP — 技術規格書

**最後更新：** 2026-05-15  
**狀態：** 🟡 Phase 1 進行中

---

## 📋 總覽

| 項目 | 內容 |
|------|------|
| 產品名稱 | MaidLedger |
| 目標用戶 | 僱主 + 外傭 (FDW) |
| 核心功能 | 智能收據掃描 + AI 對話記帳 + 價格警告 |
| 平台 | Flutter (Cross-platform, 兩個獨立 App) |
| Backend | Supabase (PostgreSQL + Edge Functions) |

---

## 🛠️ Tech Stack

| 層 | 選擇 |
|---|---|
| Mobile | Flutter (helper_app + employer_app 分離) |
| Backend | Supabase |
| Database | PostgreSQL |
| LLM (Receipt OCR parse) | OpenRouter `deepseek/deepseek-v4-flash:free` → Edge Function |
| LLM (Chat input parse) | Keyword engine + Gemini fallback (透過 edge function 或直接) |
| OCR | Google ML Kit (On-device, Chinese model) |
| Storage | Supabase Storage (receipts bucket) |

---

## 📁 目錄結構

```
maidledger/
├── apps/
│   ├── helper_app/           # Flutter (外傭) — 主要開發 ✅
│   │   ├── lib/
│   │   │   ├── main.dart
│   │   │   ├── features/
│   │   │   │   ├── scan/scan_screen.dart      # 📷 OCR workflow
│   │   │   │   ├── chat/chat_screen.dart      # 💬 AI Chat workflow
│   │   │   │   ├── history/history_screen.dart
│   │   │   │   └── auth/
│   │   │   │       ├── auth_provider.dart
│   │   │   │       ├── relation_gate.dart     # 🔗 Employer-helper relation
│   │   │   │       └── login_screen.dart
│   │   │   └── core/services/
│   │   │       ├── receipt_scanner_service.dart   # ML Kit OCR
│   │   │       ├── ai_booking_agent_service.dart  # Chat input parser
│   │   │       ├── relation_service.dart           # Relation check/link
│   │   │       └── supabase_client_provider.dart
│   │   └── pubspec.yaml
│   └── employer_app/         # Flutter (僱主) — ⬜ 未開始
│
├── packages/
│   ├── receipt-scanner/      # ML Kit OCR package
│   ├── receipt-parser/       # LLM parsing Flutter client
│   └── ai-booking-agent/    # Keyword-based expense parser
│
└── supabase/
    ├── functions/
    │   └── receipt-parser/    # 🌐 Edge function — OpenRouter LLM parse
    └── migrations/           # DB schema migrations
```

---

## 🔌 API 設計 (Supabase)

### Tables

```sql
-- receipts (Header)
CREATE TABLE receipts (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employer_id     UUID REFERENCES user_profiles(id) NOT NULL,
  helper_id       UUID REFERENCES user_profiles(id),
  relation_id     UUID REFERENCES employer_helper_relations(id),
  store_name      TEXT,
  store_cate      TEXT CHECK (store_cate IN (
                    'supermarket','wet_market','pharmacy',
                    'convenience','online','other')),
  location        TEXT,
  transaction_date DATE,
  raw_text        TEXT NOT NULL,         -- OCR 結果或用戶輸入文字
  image_local_path TEXT,                  -- Supabase Storage URL
  amount          DECIMAL(10,2),
  sync_status     TEXT DEFAULT 'pending',
  local_timestamp BIGINT NOT NULL,
  server_timestamp BIGINT,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- receipt_items (Line Items — 1:N with receipts)
CREATE TABLE receipt_items (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  receipt_id      UUID REFERENCES receipts(id) ON DELETE CASCADE,
  item_name       TEXT NOT NULL,
  item_raw_text   TEXT,
  qty             DECIMAL(10,3) DEFAULT 1,
  unit_price      DECIMAL(10,2),
  prd_cate        TEXT CHECK (prd_cate IN (
                    'fish','pork','beef','chicken','vegetables',
                    'rice','oil','seasoning','snack','drink',
                    'daily','other')),
  line_total      DECIMAL(10,2),
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- user_profiles
CREATE TABLE user_profiles (
  id              UUID PRIMARY KEY REFERENCES auth.users,
  role            TEXT NOT NULL CHECK (role IN ('employer','helper')),
  name            TEXT NOT NULL,
  phone           TEXT,
  short_code      CHAR(6) UNIQUE,          -- 僱主邀請碼 (如 DEMO01)
  default_location TEXT,                   -- 常用購買地點
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- employer_helper_relations
CREATE TABLE employer_helper_relations (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employer_id     UUID REFERENCES user_profiles(id),
  helper_id       UUID REFERENCES user_profiles(id),
  status          TEXT DEFAULT 'active' CHECK (status IN ('active','inactive','pending')),
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(employer_id, helper_id)
);
```

### Edge Functions

| Function | 用途 | Model |
|----------|------|-------|
| `receipt-parser` | OCR text → structured JSON | OpenRouter `deepseek/deepseek-chat-v3.1` (paid, stable) |
| `chat-parser` | Chat text → structured expense (2-stage classification) | OpenRouter `deepseek/deepseek-chat-v3.1` (paid, stable) |

---

## 🔄 Input Workflows

### Workflow A: 📷 OCR Scan (列印單)

```
相機拍攝
  ↓
FlutterImageCompress 壓縮 (~500KB)
  ↓
EXIF GPS 讀取（可選）
  ↓
Supabase Storage upload → receipts/{uuid}.jpg
  ↓
ML Kit OCR (TextRecognizer, Chinese script)
  ↓
Edge Function receipt-parser (LLM parse)
  ↓
Save receipts + receipt_items
```

### Workflow B: 💬 Chat Input (手寫單 / 快速輸入)

```
用戶輸入文字 + attach 圖片（可選）
  ↓
AIBookingAgent.parseExpense() → ExpenseIntent
  ↓
Parse items[] from intent
  ↓
如果有圖片：
  ├─ Compress
  ├─ Supabase Storage upload
  └─ image_url = Storage URL
  ↓
Location Resolution:
  1. EXIF GPS → Reverse geocode → 地點名
  2. user_profiles.default_location
  3. 都冇 → null
  ↓
Save receipts + receipt_items
  - raw_text = 用戶輸入文字
  - items = parsed items[]
  - image_url = Storage URL
  - location = resolved
```

---

## 🔗 Employer-Helper Relation Logic

### 觸發時機
```
App 啟動 → AuthGate → RelationGate
  ↓
checkRelationStatus(userId)
  ↓
有 active relation → 進入 MainNavigationScreen
冇 active relation → 彈「連接僱主」對話框
```

### Link 方式
- **6位 short_code**（如 `DEMO01`）— 主要方式
- **UUID** — 向後兼容

### 核心流程
```dart
// 1. 用戶輸入 short_code 或 UUID
// 2. RelationService.linkToEmployer(helperId, code)
//    → 先用 short_code 查詢 user_profiles
//    → 冇結果再用 UUID
// 3. 成功 → 建立 employer_helper_relations record
// 4. 失敗 → 顯示 error，可 retry
```

### 「稍後」按鈕
- 按「稍後」→ Dialog dismiss → 進入 app
- 需要 relation 的操作（save receipt）會再彈 dialog

---

## 📱 App 導航架構

```
┌──────────────────────────────────────────────────────────┐
│                      helper_app                            │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  AuthGate (Firebase Auth check)                          │
│    ↓                                                    │
│  RelationGate (Employer link check)                      │
│    ↓                                                    │
│  MainNavigationScreen (BottomNavigationBar)              │
│    ├── 📷 Scan Tab (OCR Workflow)                       │
│    ├── 💬 Chat Tab (AI Booking Agent)                   │
│    └── 📜 History Tab (Receipt list)                     │
│                                                          │
└──────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────┐
│                     employer_app                          │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  AuthGate                                                │
│    ↓                                                    │
│  MainScreen                                              │
│    ├── 📋 Receipts Tab (Helper 上報的 receipt list)       │
│    ├── 🔢 My Code Tab (顯示 employer short_code)         │
│    └── ⚙️ Settings Tab                                   │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

---

## ⚠️ 待確認 / 進行中

| 項目 | 狀態 | 備註 |
|------|------|------|
| helper_app main flow | ✅ 完成 | Scan + Chat + History |
| OCR with ML Kit Chinese | ✅ 完成 | TextRecognitionScript.chinese |
| Edge function receipt-parser | ✅ 完成 | OpenRouter DeepSeek V4 (paid) |
| Edge function chat-parser | ✅ 完成 | 2-stage classification, all text via LLM |
| Image upload to Supabase Storage | ✅ 完成 | |
| EXIF GPS location extraction | ✅ 完成 | `exif` package + Nominatim reverse geocode |
| Chat attach image | ✅ 完成 | ImagePicker + Storage upload |
| Chat → receipts + items save | ✅ 完成 | receipts + receipt_items schema |
| Prd/Store categories dynamic read | ✅ 完成 | Edge function reads from DB at startup |
| Row-reconstructed OCR format | ✅ 完成 | `_groupByRow()` in receipt_scanner_service |
| 2-stage input classification (is_expense) | ✅ 完成 | Prevents conversational abuse |
| employer_app | ⬜ 未開始 | 需要 My Code + Receipt list |
| user_profiles.default_location | ⬜ 待做 | Location fallback for chat |
| Rate limiting | ✅ 完成 | 6/min + 30min block |
| Raw amount extraction + validation | ✅ 完成 | Regex-based pre-LLM extraction |
| Shop standardization (shops + aliases) | ✅ 完成 | shop_matching_service.dart |
| Multi-language product matching | ✅ 完成 | isda/ikan/bangus support |
| Price history write flow | ✅ 完成 | price_history table |
| Price alert engine | ✅ 完成 | weather suppression |
| Weather check function | ✅ 完成 | HK Observatory API stub |

---

## 📅 開發順序

```
Phase 1 (進行中)
├── receipt-scanner ✅
├── receipt-parser (edge) ✅
├── ai-booking-agent ✅ (keyword engine)
├── Chat attach image + EXIF location ⬜
├── Chat save → receipts + receipt_items ⬜
└── employer_app My Code tab ⬜

Phase 2
├── employer_app receipt list + review
└── Reverse geocode (GPS → 地點名)

Phase 3
└── Wet market relative pricing
```

---

## 🔗 外部依賴

| Service | 用途 |
|---------|------|
| Google ML Kit | On-device OCR |
| OpenRouter API | LLM receipt parsing |
| Supabase | DB + Storage + Edge Functions |
| Firebase Auth | 用戶認證 |

---

## 📝 ARCHITECTURE.md

詳細的 workflow、各層 logic、error handling、DB schema 對照，見 [ARCHITECTURE.md](./ARCHITECTURE.md)。

---

## 📝 修改記錄

| 日期 | 修改內容 |
|------|---------|
| 2026-05-15 | 更新 OCR workflow、Chat workflow、Relation logic、Edge function |
| 2026-05-15 | LLM provider 改為 OpenRouter DeepSeek V4 Flash |
| 2026-05-15 | 加入 receipt_items（normalized item storage）|
| 2026-05-15 | 加入 short_code（6位僱主邀請碼）|
| 2026-05-13 | 初始版本 |
| 2026-05-18 | 加入眾包價格系統（shops, shop_aliases, price_history, price_alerts）|
| 2026-05-18 | chat-parser: raw amount extraction + LLM output validation |
| 2026-05-18 | multi-language product matching（魚/isda/ikan）|
| 2026-05-18 | price-alert-engine with weather suppression | |