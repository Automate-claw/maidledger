# Edge Functions Documentation

Last updated: 2026-05-26

## Active Edge Functions

| Function | Trigger | Input | Output | DB Writes |
|---|---|---|---|---|
| `chat-orchestrate` | Flutter `ai_booking_agent_service` | `{text, user_id, location?}` | `{success, receipt_id, needs_review, errors}` | `receipts`, `receipt_items`, `shops`, `price_history` |
| `chat-parser` | `chat-orchestrate` (internal) | `{raw_text}` | LLM parsed items | None |
| `receipt-orchestrate` | Flutter `scan_screen` (fire-and-forget) | `{receipt_id}` | Processing result | Calls other functions |
| `receipt-vision` | `receipt-orchestrate` (internal) | `{receipt_id}` | Vision LLM parsed result | None |
| `receipt-parse` | `receipt-orchestrate` (internal) | `{ocr_raw_text, ocr_reconstructed?, raw_text?}` | Parsed receipt | None |
| `receipt-writer` | `receipt-orchestrate` (internal) | `{action, ...}` | Write result | `receipts`, `receipt_items`, `price_history` |
| `shop-manager` | `receipt-orchestrate`, `chat-orchestrate` (internal) | `{action, ...}` | Shop match/create result | `shops`, `shop_aliases` |
| `product-manager` | `receipt-orchestrate`, `chat-orchestrate` (internal) | `{action, ...}` | Product match/create result | `master_products`, `product_aliases` |
| `notification-broadcast` | Flutter `scan_screen` | `{receipt_id}` | Notification sent | None (real-time only) |
| `price-alert-engine` | Flutter `chat_screen` | `{type, receipt_id, ...}` | Alert check result | None |
| `daily-summary` | Flutter `history_screen` (share button) | None (uses auth) | `{success, text}` | None (read-only) |

---

## Function Details

### chat-orchestrate
**Purpose:** Coordinator for chat-based expense entry. All business logic for chat input.

**Caller:** `helper_app/lib/core/services/ai_booking_agent_service.dart` → `POST /functions/v1/chat-orchestrate`

**Flow:**
```
chat-orchestrate → chat-parser → receipt-writer → shop-manager → product-manager
```

**Input:**
```json
{ "text": "fish 30", "user_id": "uuid", "location": "西九" }
```

**Output:**
```json
{ "success": true, "receipt_id": "uuid", "needs_review": false, "errors": [] }
```

---

### chat-parser
**Purpose:** LLM parsing of raw user chat text into structured items.

**Caller:** `chat-orchestrate` (internal `callFunction`)

**Input:** `{raw_text: "魚 30蚊"}`
**Output:** Parsed item array with name, qty, price, category

---

### receipt-orchestrate
**Purpose:** Coordinator for receipt processing (scan). Fires on receipt INSERT via DB webhook.

**Caller:** `helper_app/lib/features/scan/scan_screen.dart` → `POST /functions/v1/receipt-orchestrate` (fire-and-forget, with cron fallback)

**Flow:**
```
receipt-orchestrate → receipt-vision → receipt-writer
                     → shop-manager → product-manager → receipt-writer
```

**Input:** `{receipt_id: "uuid"}`
**Output:** Processing status (errors are isolated per item)

**Note:** Fallback cron job runs every 5 min to catch failed webhooks.

---

### receipt-vision
**Purpose:** Vision LLM parsing for receipt images. Used by `receipt-orchestrate`.

**Caller:** `receipt-orchestrate` (internal `callFunction`)

**Input:** `{receipt_id: "uuid"}` (reads image URL from DB)
**Output:** Structured receipt data with store_name, items, amounts

---

### receipt-parse
**Purpose:** LLM parsing for OCR text (text-based receipts, not vision).

**Caller:** `receipt-orchestrate` (internal `callFunction`)

**Input:** `{ocr_raw_text, ocr_reconstructed?, raw_text?}`
**Output:** Structured receipt data

---

### receipt-writer
**Purpose:** Writes parsed receipt data to DB. Handles all DB writes for receipt flow.

**Caller:** `receipt-orchestrate`, `chat-orchestrate` (internal)

**Actions:**
- `writeReceipt` — update parsed fields on existing receipt
- `writeItems` — insert receipt_items records
- `writePriceHistory` — insert price_history records
- `writeShopLink` — update receipt.shop_id

---

### shop-manager
**Purpose:** Shop matching, creation and alias management.

**Caller:** `receipt-orchestrate`, `chat-orchestrate` (internal)

**Actions:**
- `match` — find existing shop by raw name
- `create` — create new shop
- `upsert` — match or create
- `upsertAlias` — link raw name to shop
- `get` — retrieve shop by ID

---

### product-manager
**Purpose:** Product matching, creation and alias management.

**Caller:** `receipt-orchestrate`, `chat-orchestrate` (internal)

**Actions:**
- `match` — find existing product by name
- `create` — create new master_product
- `upsert` — match or create
- `upsertAlias` — link raw name to master_product
- `get` — retrieve product by ID

---

### notification-broadcast
**Purpose:** Triggered by DB webhook on receipt INSERT. Broadcasts to employer's Realtime channel.

**Caller:** `helper_app/lib/features/scan/scan_screen.dart` → `POST /functions/v1/notification-broadcast`

**Input:** `{receipt_id}` (reads receipt data from DB)
**Output:** None (fires Realtime event)

---

### price-alert-engine
**Purpose:** Checks if new price is significantly different from baseline. Fires notification if alert.

**Caller:** `helper_app/lib/features/chat/chat_screen.dart` → `POST /functions/v1/price-alert-engine`

**Input:** `{type: "new_price", receipt_id, master_product_id, new_price, unit}`

---

### daily-summary
**Purpose:** Generates formatted daily summary text for sharing. Queries receipts in 06:00-06:00 window.

**Caller:** `helper_app/lib/features/history/history_screen.dart` (share button) → `POST /functions/v1/daily-summary`

**Input:** None (uses auth header for user)
**Output:** `{success: true, text: "📋 每日採購摘要\n🗓️ ..."}`

---

## Deprecated/Removed

### receipt-parser (DELETED 2026-05-26)
**Reason:** Function was superseded by `receipt-vision`. The `_callEdgeLLM()` method in `scan_screen.dart` was dead code — never invoked anywhere.

---

## All Edge Functions (Current State)

```
supabase/functions/
├── chat-orchestrate/      ✅ Active
├── chat-parser/           ✅ Active
├── daily-summary/         ✅ Active
├── notification-broadcast/✅ Active
├── price-alert-engine/     ✅ Active
├── product-manager/        ✅ Active
├── receipt-benchmark/     ⚠️ Test only (manual trigger)
├── receipt-orchestrate/    ✅ Active
├── receipt-parse/         ✅ Active
├── receipt-vision/        ✅ Active
├── receipt-writer/        ✅ Active
├── shop-manager/          ✅ Active
└── weather-check/         ⚠️ Status unclear (cron/scheduled job?)
```

---

## Data Flow Summary

```
Flutter App (Helper)
├── Chat input → ai_booking_agent → chat-orchestrate → [chat-parser, receipt-writer, shop-manager, product-manager]
└── Scan input → scan_screen → receipt-orchestrate → [receipt-vision, receipt-writer, shop-manager, product-manager]
    └── notification-broadcast (fires on receipt INSERT)

Flutter App (Employer)
└── Share button → daily-summary (read-only)

Both apps use Supabase Realtime for live updates.
```