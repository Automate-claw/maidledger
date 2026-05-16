# MaidLedger — Architecture & Workflow Documentation

**最後更新：** 2026-05-17
**用途：** 維護參考 — 快速定位 logic 修改位置

---

## 📁 關鍵檔案位置

```
maidledger/
├── apps/
│   ├── helper_app/lib/
│   │   ├── main.dart                           # App 入口 + AuthGate + RelationGate
│   │   ├── features/
│   │   │   ├── scan/scan_screen.dart           # 📷 OCR 掃描 workflow
│   │   │   ├── chat/chat_screen.dart           # 💬 AI Chat 記帳 workflow
│   │   │   ├── history/history_screen.dart      # 📜 Receipt history
│   │   │   ├── settings/settings_screen.dart   # ⚙️ Settings (logout + language)
│   │   │   └── auth/
│   │   │       ├── auth_provider.dart           # Auth state management
│   │   │       ├── relation_gate.dart           # 🔗 Relation check + link dialog
│   │   │       └── login_screen.dart            # Login UI
│   │   └── core/services/
│   │       ├── ai_booking_agent_service.dart   # Chat → Edge call (rate limit aware)
│   │       ├── receipt_scanner_service.dart     # ML Kit OCR
│   │       ├── relation_service.dart            # Relation check/link (short_code)
│   │       └── supabase_client_provider.dart    # Supabase init
│   │
│   └── employer_app/lib/
│       ├── main.dart                           # App 入口 + NotificationService
│       ├── features/
│       │   ├── receipts/receipts_screen.dart   # 📜 收據列表
│       │   ├── mycode/my_code_screen.dart       # 🔢 我的邀請碼 (short_code)
│       │   └── settings/settings_screen.dart    # ⚙️ 設定 (notification toggle)
│       └── core/services/
│           └── supabase_client_provider.dart
│
├── packages/
│   ├── receipt-parser/                          # LLM parsing service (Flutter side)
│   ├── ai-booking-agent/                        # Multi-language expense parser
│   └── receipt-scanner/                         # Core OCR package
│
└── supabase/
    ├── functions/
    │   ├── chat-parser/                         # 🌐 AI Chat 解析 + rate limiting
    │   ├── receipt-parser/                      # 🌐 OCR  receipt 解析
    │   └── notification-broadcast/              # 🌐 收據上傳 → Realtime notification
    └── migrations/                              # DB schema
```

---

## 🗄️ Database Schema Summary

### receipts (Header Table)
```sql
id              UUID PRIMARY KEY
employer_id     UUID → user_profiles(id)
helper_id       UUID → user_profiles(id)
relation_id     UUID → employer_helper_relations(id)

store_name      TEXT
store_cate      TEXT          -- supermarket|wet_market|pharmacy|convenience|online|other
location        TEXT
transaction_date DATE
raw_text        TEXT NOT NULL
image_local_path TEXT
amount          DECIMAL(10,2)

sync_status     TEXT DEFAULT 'pending'
local_timestamp BIGINT NOT NULL
created_at      TIMESTAMPTZ DEFAULT NOW()
```

### receipt_items (Line Items - 1:N with receipts)
```sql
id              UUID PRIMARY KEY
receipt_id      UUID → receipts(id) ON DELETE CASCADE
item_name       TEXT NOT NULL
item_raw_text   TEXT
qty             DECIMAL(10,3) DEFAULT 1
unit_price      DECIMAL(10,2)
prd_cate        TEXT           -- fish|pork|beef|chicken|vegetables|rice|oil|seasoning|snack|drink|daily|other
line_total      DECIMAL(10,2)
created_at      TIMESTAMPTZ DEFAULT NOW()
```

### user_profiles
```sql
id              UUID PRIMARY KEY → auth.users(id)
role            TEXT CHECK (employer|helper)
name            TEXT NOT NULL
phone           TEXT
short_code      VARCHAR(20) UNIQUE   -- 僱主邀請碼（如 HE5KZV）
created_at      TIMESTAMPTZ DEFAULT NOW()
```

### employer_helper_relations
```sql
id              UUID PRIMARY KEY
employer_id     UUID → user_profiles(id)
helper_id       UUID → user_profiles(id)
status          TEXT DEFAULT 'active' CHECK (active|inactive|pending)
created_at      TIMESTAMPTZ DEFAULT NOW()
UNIQUE(employer_id, helper_id)
```

### chat_rate_limits (Rate Limiting for Chat)
```sql
id              UUID PRIMARY KEY DEFAULT gen_random_uuid()
user_id         TEXT NOT NULL
is_expense      BOOLEAN NOT NULL DEFAULT false
created_at      TIMESTAMPTZ DEFAULT NOW()
-- Index: (user_id, created_at), (user_id, is_expense, created_at)
```

### store_categories / prd_categories
```sql
store_categories: code, name_tc, name_en, description, display_order
prd_categories:   code, name_tc, name_en, description, display_order
```

---

## 🔄 Workflow 總覽

```
┌─────────────────────────────────────────────────────────────┐
│                    MaidLedger System                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐         ┌──────────────────────┐          │
│  │  Helper App  │ ──────→ │  chat-parser Edge   │          │
│  │   (Chat)     │         │  LLM → expense?      │          │
│  └──────────────┘         │  + rate limiting     │          │
│                           └──────────┬───────────┘          │
│                                      │                        │
│  ┌──────────────┐         ┌──────────┴───────────┐          │
│  │  Helper App  │ ──────→ │  receipt-parser Edge  │          │
│  │   (Scan)    │         │  OCR → items[]        │          │
│  └──────────────┘         └──────────┬───────────┘          │
│                                      │                        │
│                                      ▼                        │
│  ┌──────────────────────────────────────────────┐           │
│  │          INSERT receipts + receipt_items      │           │
│  └──────────────────────┬───────────────────────┘           │
│                         │                                    │
│                         ▼                                    │
│  ┌──────────────────────────────────────────────┐           │
│  │       notification-broadcast Edge Fn         │           │
│  │  → Supabase Realtime → Employer App          │           │
│  │  → flutter_local_notifications (local push)  │           │
│  └──────────────────────────────────────────────┘           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 💬 Workflow: Chat (helper_app)

```
用戶輸入文字 → AIBookingAgent.parseExpense(text, userId)
    ↓
chat-parser Edge Function (LLM via OpenRouter)
    ↓
┌─ is_expense=true → 分析 → 回應 ✅
└─ is_expense=false → friendly guidance (唔係 error)
    ↓
Rate Limit Check:
  ├─ 1分鐘 >6次 → ⏱️ 請稍後再試
  └─ 2分鐘 >5次 non-expense → 🚫 暫停30分鐘
    ↓
buildResponse(intent)
    ↓
如果 confidence>0.7 + 有金額 → _showSaveDialog()
    ↓
INSERT receipts + receipt_items
    ↓
notification-broadcast (non-blocking)
```

### Rate Limiting Logic
```typescript
// 1分鐘最多 6次請求
if (reqCount >= 6) → { rate_limited: true, retry_after: 60 }

// 2分鐘內 >5次非開支 → 30分鐘 block
if (nonExpCount >= 5) → { rate_limited: true, retry_after: 1800 }
```

### Chat → DB Schema
| Chat Field | receipts table | receipt_items |
|------------|---------------|----------------|
| `rawText` | `raw_text` | — |
| `items[]` | — | `item_name` (逐 item 一行) |
| `amount` | `amount` | `unit_price` |
| `image_url` | `image_local_path` | — |

---

## 📷 Workflow: OCR Scan (helper_app)

```
Camera Capture → Compress (~500KB)
    ↓
EXIF GPS (如果可用) → location
    ↓
ML Kit OCR (TextRecognizer, Chinese model)
    ↓
receipt-parser Edge Function (LLM via OpenRouter)
    ↓
Save receipts + receipt_items
    ↓
notification-broadcast (non-blocking)
```

---

## 🔢 Workflow: My Code (employer_app)

```
user_profiles.short_code → Display (6-char, e.g. HE5KZV)
    ↓
_worker輸入 short_code → RelationService.linkToEmployer()
    ↓
INSERT / UPDATE employer_helper_relations (status='active')
```

---

## 🔔 Workflow: Notifications (employer_app)

```
Helper INSERT receipt
    ↓
notification-broadcast Edge Function
    ↓
Supabase Realtime channel: notifications:{employer_id}
    ↓
Employer App → onBroadcast('new_receipt')
    ↓
flutter_local_notifications.show() → 本地推送
    ↓
用戶可在 Settings 關閉通知 (notificationEnabledProvider)
```

---

## ⚙️ Settings Screens

### Helper App (Settings)
- Profile card (name, role)
- 語言切換 (繁體中文 / English) → localeProvider (SharedPreferences)
- 版本 1.0.0
- 登出 (authStateProvider.signOut())

### Employer App (Settings)
- Profile card
- 通知設定 SwitchListTile → notificationEnabledProvider (SharedPreferences)
- 語言 / 版本 / 使用條款 (static)
- 登出

---

## 🌐 Edge Functions

### chat-parser
**URL:** `POST /functions/v1/chat-parser`
**Rate limits:** 6 req/min per user; >5 non-expense in 2min → 30min block
**Logic:** All inputs → LLM → expense=true OR friendly guidance

**Request:**
```json
{ "text": "魚 30蚊", "user_id": "uuid-or-anonymous" }
```

**Response (expense):**
```json
{
  "is_expense": true,
  "completeness": "good",
  "total_amount": 30,
  "items": [{"item_name": "魚", "unit_price": 30, "prd_cate": "fish"}],
  "store_cate": "wet_market",
  "parse_confidence": 0.9
}
```

**Response (non-expense):**
```json
{
  "is_expense": false,
  "completeness": "invalid",
  "response_message": "👋 你好！我係你的記帳助手...\n• 魚 30蚊\n• 超市買餸 120元",
  "rate_limited": false
}
```

**Response (rate limited):**
```json
{
  "is_expense": false,
  "rate_limited": true,
  "retry_after": 60,
  "response_message": "⏱️ 你一分鐘內請求太多，請稍後再試。"
}
```

### notification-broadcast
**Trigger:** Called by helper_app after INSERT receipts
**Action:** Broadcast to Supabase Realtime channel `notifications:{employer_id}`

---

## 📝 修改記錄

| 日期 | 修改內容 |
|------|---------|
| 2026-05-15 | 加入 OCR + LLM workflow、Chat + Image workflow、Relation logic、Edge function |
| 2026-05-15 | 切換 LLM provider：Gemini → OpenRouter DeepSeek V4 |
| 2026-05-15 | 加入 receipt_items table（normalized item storage）|
| 2026-05-15 | 加入 short_code（6位僱主邀請碼）|
| 2026-05-15 | 加入 store_categories + prd_categories master tables |
| 2026-05-15 | 重寫 chat-parser edge function（2-stage classification）|
| 2026-05-16 | chat-parser 取代 Gemini direct call |
| 2026-05-16 | 加入 notification-broadcast (Realtime notification) |
| 2026-05-16 | 加入 flutter_local_notifications (employer app) |
| 2026-05-16 | 加入 short_code migration + DB update |
| 2026-05-16 | Helper app: Settings screen (logout + language) |
| 2026-05-16 | Push to GitHub: Automate-claw/maidledger |
| 2026-05-17 | chat-parser: 簡化 logic（移除預檢，直接 LLM）|
| 2026-05-17 | chat-parser: 加入 rate limiting（6/min, >5 non-expense→30min block）|
| 2026-05-17 | chat-parser: 非開支 → friendly guidance，唔係 error |