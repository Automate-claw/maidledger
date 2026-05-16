# MaidLedger — Architecture & Workflow Documentation

**最後更新：** 2026-05-15  
**用途：** 維護參考 — 快速定位 logic 修改位置

---

## 📁 關鍵檔案位置

```
maidledger/
├── apps/helper_app/lib/
│   ├── main.dart                          # App 入口 + AuthGate + RelationGate
│   ├── features/
│   │   ├── scan/scan_screen.dart          # 📷 OCR 掃描 workflow
│   │   ├── chat/chat_screen.dart          # 💬 AI Chat 記帳 workflow
│   │   ├── history/history_screen.dart     # 📜 Receipt history
│   │   └── auth/
│   │       ├── auth_provider.dart         # Auth state management
│   │       ├── relation_gate.dart          # 🔗 Relation check + link dialog
│   │       └── login_screen.dart           # Login UI
│   └── core/services/
│       ├── receipt_scanner_service.dart    # ML Kit OCR
│       ├── receipt_scanner_provider.dart   # Riverpod provider
│       ├── relation_service.dart           # Relation check/link (short_code)
│       ├── ai_booking_agent_service.dart  # Keyword engine for chat input
│       └── supabase_client_provider.dart   # Supabase init
│
├── packages/
│   ├── receipt-parser/                     # LLM parsing service (Flutter side)
│   ├── ai-booking-agent/                  # Multi-language expense parser
│   └── receipt-scanner/                    # Core OCR package
│
└── supabase/
    ├── functions/receipt-parser/          # 🌐 Edge function — LLM parse via OpenRouter
    └── migrations/                         # DB schema
```

---

## 🔄 Workflow 總覽

```
┌─────────────────────────────────────────────────────────────┐
│                      MaidLedger Helper App                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐   │
│  │   📷 Scan    │    │   💬 Chat    │    │  📜 History  │   │
│  │  (OCR Tab)   │    │ (Text Tab)   │    │              │   │
│  └──────┬───────┘    └──────┬───────┘    └──────────────┘   │
│         │                   │                                │
│         ▼                   ▼                                │
│  ┌──────────────┐    ┌──────────────┐                        │
│  │ Image Input  │    │ Text Input   │                        │
│  │ + Camera     │    │ + (Optional) │                        │
│  │              │    │ + Image     │                        │
│  └──────┬───────┘    └──────┬───────┘                        │
│         │                   │                                │
│         ▼                   ▼                                │
│  ┌──────────────┐    ┌──────────────┐                        │
│  │  📷 Camera   │    │ AIBooking    │                        │
│  │  Capture     │    │ Agent        │                        │
│  └──────┬───────┘    └──────┬───────┘                        │
│         │                   │                                │
│         ▼                   ▼                                │
│  ┌──────────────┐    ┌──────────────┐                        │
│  │ Compress     │    │ Parse text   │                        │
│  │ (500KB max)  │    │ → items[]    │                        │
│  └──────┬───────┘    └──────┬───────┘                        │
│         │                   │                                │
│         ▼                   │                                │
│  ┌──────────────┐           │                                │
│  │ 🗜️ EXIF GPS  │           │                                │
│  │ → location   │           │                                │
│  └──────┬───────┘           │                                │
│         │                   │                                │
│         ▼                   ▼                                │
│  ┌──────────────────────────────────┐                        │
│  │        Location Resolution        │                        │
│  │  1. EXIF GPS → 地點名             │                        │
│  │  2. fallback: user.default_location │                      │
│  │  3. 都冇 → null (可後補)           │                        │
│  └──────────────┬───────────────────┘                        │
│                 │                                             │
│                 ▼                                             │
│  ┌──────────────────────────────────────┐                    │
│  │       Receipt Entity Builder          │                    │
│  │  - raw_text                           │                    │
│  │  - items[]                            │                    │
│  │  - location                           │                    │
│  │  - image_url (Supabase Storage)       │                    │
│  └──────────────┬───────────────────────┘                    │
│                 │                                             │
│                 ▼                                             │
│  ┌──────────────────────────────────────┐                    │
│  │         Save to Supabase               │                    │
│  │  INSERT receipts + receipt_items       │                    │
│  └──────────────────────────────────────┘                    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 📷 Workflow 1: OCR Scan (scan_screen.dart)

### 觸發流程
```
用戶按下相機按鈕
  ↓
CameraController.takePicture()
  ↓
FlutterImageCompress.compressWithFile() → ~500KB
  ↓
EXIF 讀取 GPS (如果可用)
  ↓
Supabase Storage upload → receipts/{uuid}.jpg
  ↓
ML Kit OCR (TextRecognizer, Chinese model)
  ↓
Supabase Edge Function → LLM parse (DeepSeek V4 Flash via OpenRouter)
  ↓
Save receipts + receipt_items
```

### 關鍵程式碼位置

| 功能 | 位置 |
|------|------|
| 壓縮圖片 | `scan_screen.dart` → `_compressImage()` |
| 上傳 Storage | `scan_screen.dart` → `_uploadToStorage()` |
| EXIF 讀取 | (待實現) → `_readExifLocation()` |
| OCR | `receipt_scanner_service.dart` → `scanFromFile()` |
| LLM Edge | `scan_screen.dart` → `_callEdgeLLM()` |
| DB Save | `scan_screen.dart` → `_saveReceiptToDb()` |

### Edge Function Response Schema

```dart
class ReceiptParseResult {
  String? storeName;
  String storeCate;        // supermarket|wet_market|pharmacy|convenience|online|other
  String? location;
  double? totalAmount;
  String? transactionDate;
  List<ParsedItem> items;
  double parseConfidence;
  bool isSuccess;
  String? errorMessage;
}

class ParsedItem {
  String itemName;
  String itemRawText;
  double qty;
  double? unitPrice;
  String prdCate;  // fish|pork|beef|chicken|vegetables|rice|oil|seasoning|snack|drink|daily|other
}
```

### Error Handling
- Edge function 返回 `{"error": "..."}` → Flutter throw Exception → 顯示 error snackbar
- `store_name=null AND amount=null` → 視為 LLM parse 失敗 → save 時 skip（不允許 save 不完整的 receipt）

---

## 💬 Workflow 2: Chat Text Input (chat_screen.dart)

### 觸發流程
```
用戶輸入文字 + (可選) attach 圖片
  ↓
AIBookingAgent.parseExpense(text) → ExpenseIntent
  ↓
Parse items[] from intent (intent.items 或 keyword extraction)
  ↓
如果 attach 了圖片：
  ├─ Compress
  ├─ 上傳 Supabase Storage
  └─ image_url = Storage URL
如果冇圖片：image_url = null
  ↓
Location Resolution:
  1. EXIF GPS → 地點名（如果圖片有 GPS）
  2. user_profiles.default_location（如果有的話）
  3. 都冇 → null
  ↓
Save to receipts + receipt_items
  - raw_text = 用戶輸入的文字（整段）
  - items = parsed items[]
  - image_url = attached image URL 或 null
  - location = resolved location
```

### AIBookingAgent.parseExpense() Logic

```dart
// 優先用 keyword engine（免費、快速）
if (keywordMatch.confidence > 0.85) return keywordResult;

// Fall back to LLM (if api key available)
// Gemini via direct HTTP call (deprecated — should route through edge)
```

### 關鍵程式碼位置

| 功能 | 位置 |
|------|------|
| Chat input UI | `chat_screen.dart` → `_sendMessage()` |
| AIBookingAgent parse | `ai_booking_agent_service.dart` → `parseExpense()` |
| Keyword engine | `ai_booking_agent_service.dart` → `_detectFromKeywords()` |
| Image attach | (待實現) → Camera button in ChatScreen |
| Save expense | `chat_screen.dart` → `_saveExpense()` |
| EXIF location | (待實現) → `_extractLocationFromImage()` |

### ExpenseIntent Schema

```dart
class ExpenseIntent {
  String rawText;           // 原始用戶輸入
  String intent;            // buy|food|transport|market|supermarket|unknown
  String? category;         // food|transport|household|other
  double? amount;           // 總金額（如果有）
  double confidence;        // 0.0-1.0
  List<String> items;       // 物品名稱列表（由 AI parse 出）
  String? note;
  bool fallback;            // 是否係 fallback keyword engine
}
```

### Chat → DB Schema 對照

| Chat Field | receipts table | receipt_items |
|------------|---------------|---------------|
| `rawText` | `raw_text` | — |
| `intent.items[]` | — | `item_name` (逐 item 一行) |
| `amount` | `amount` | `unit_price` (第一個 item 的 price 或 total) |
| `image_url` | `image_local_path` | — |
| `location` | `location` | — |
| `datetime` | `transaction_date` | — |

---

## 🔗 Workflow 3: Relation Check (relation_gate.dart)

### 觸發時機
```
App 啟動 → AuthGate → RelationGate
  ↓
checkRelationStatus(userId)
  ↓
有 active relation → 進入 MainNavigationScreen
冇 active relation → 彈「連接僱主」對話框
  ├─ 用戶輸入 6 位 short_code (如 DEMO01)
  ├─ 或輸入 UUID (向後兼容)
  ↓
RelationService.linkToEmployer(helperId, code)
  ↓
成功 → 進入 App
失敗 → 顯示 error，可 retry
```

### Relation Check Logic

```dart
Future<RelationStatus> checkRelationStatus(String userId) async {
  // Query employer_helper_relations WHERE helper_id = userId AND status = 'active'
  // Return: hasActiveRelation (bool) + relations[]
}

// Resolution order for employer code:
// 1. Try short_code (6-char, e.g. "DEMO01") first
// 2. Fall back to UUID
```

### 用戶可以「稍後」再連接
- 按「稍後」→ Dialog dismiss → 進入 app 但有限制
- 任何需要 relation 的操作（如 save receipt）會再彈 "需要連接僱主" dialog

### 關鍵程式碼位置

| 功能 | 位置 |
|------|------|
| RelationGate widget | `relation_gate.dart` → `RelationGate` class |
| Dialog UI | `relation_gate.dart` → `_EmployerLinkDialog` class |
| Link service | `relation_service.dart` → `linkToEmployer()` |
| Status check | `relation_service.dart` → `checkRelationStatus()` |
| short_code resolution | `relation_service.dart` → `_resolveEmployer()` |

---

## 🗜️ Workflow 4: Image EXIF Location Extraction

### 實現方式

```dart
// 使用 exif package 讀取 EXIF metadata
import 'package:exif/exif.dart';

Future<String?> _extractLocationFromImage(String imagePath) async {
  final bytes = File(imagePath).readAsBytes();
  final tags = await readExifFromBytes(bytes);

  // GPS info in EXIF
  final lat = tags['GPS GPSLatitude'];
  final latRef = tags['GPS GPSLatitudeRef']; // N or S
  final lon = tags['GPS GPSLongitude'];
  final lonRef = tags['GPS GPSLongitudeRef']; // E or W

  if (lat == null || lon == null) return null;

  // Convert to decimal degrees
  final latitude = _parseGpsCoordinate(lat, latRef);
  final longitude = _parseGpsCoordinate(lon, lonRef);

  // Reverse geocode to location name
  return await _reverseGeocode(latitude, longitude);
}
```

### Fallback Chain
```
圖片 EXIF GPS
  → 有 → Reverse geocode → "元朗" / "觀塘" / etc.
  → 冇 → 嘗試 user_profiles.default_location
           → 冇 → null (可後補)
```

---

## 🗄️ Database Schema Summary

### receipts (Header Table)
```sql
id              UUID PRIMARY KEY
employer_id     UUID → user_profiles(id)
helper_id       UUID → user_profiles(id)
relation_id     UUID → employer_helper_relations(id)

store_name      TEXT          -- 店舖名（可為 null）
store_cate      TEXT          -- supermarket|wet_market|pharmacy|convenience|online|other
location        TEXT          -- 地區（可為 null）
transaction_date DATE          -- 交易日期（可為 null）
raw_text        TEXT NOT NULL -- 原始文字（OCR 結果或用戶輸入）
image_local_path TEXT         -- Supabase Storage URL（可為 null）
amount          DECIMAL(10,2) -- 總金額（可為 null）

sync_status     TEXT DEFAULT 'pending'
local_timestamp BIGINT NOT NULL
created_at      TIMESTAMPTZ DEFAULT NOW()
```

### receipt_items (Line Items - 1:N with receipts)
```sql
id              UUID PRIMARY KEY
receipt_id      UUID → receipts(id) ON DELETE CASCADE

item_name       TEXT NOT NULL
item_raw_text   TEXT               -- 原始 OCR 行（可為 null）
qty             DECIMAL(10,3) DEFAULT 1
unit_price      DECIMAL(10,2)     -- 單價（可為 null）
prd_cate        TEXT               -- fish|pork|beef|chicken|vegetables|rice|oil|seasoning|snack|drink|daily|other
line_total      DECIMAL(10,2)      -- 該行總額（可為 null）
created_at       TIMESTAMPTZ DEFAULT NOW()
```

### user_profiles
```sql
id              UUID PRIMARY KEY → auth.users(id)
role            TEXT CHECK (employer|helper)
name            TEXT NOT NULL
phone           TEXT
short_code      CHAR(6) UNIQUE   -- 僱主邀請碼（如 DEMO01）
default_location TEXT             -- 常用購買地點（AI chatbot 用）
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

---

## 🌐 Edge Function: receipt-parser

**URL:** `POST /functions/v1/receipt-parser`

**Request:**
```json
{
  "raw_text": "惠康超級市場\n總額 $123.45\n雞肉 $45.00"
}
```

**Response (success):**
```json
{
  "store_name": "惠康",
  "store_cate": "supermarket",
  "location": null,
  "total_amount": 123.45,
  "transaction_date": null,
  "items": [
    {"item_name": "雞肉", "item_raw_text": "雞肉 $45.00", "qty": 1, "unit_price": 45, "prd_cate": "chicken"}
  ],
  "parse_confidence": 0.9,
  "raw_text": "惠康超級市場\n總額 $123.45\n雞肉 $45.00"
}
```

**Response (error):**
```json
{
  "error": "Unexpected token...",
  "raw_text": "..."
}
```

**Model:** `deepseek/deepseek-v4-flash:free` via OpenRouter

---

## 📍 Location 實現注意點

1. **Android 权限**：需要在 `AndroidManifest.xml` 加入 `android.permission.ACCESS_FINE_LOCATION`
2. **用戶隱私**：只讀取已拍攝照片的 EXIF，唔主動開啟定位
3. **照片設定**：用戶需要確保相機設定入面開了「保存位置資訊」
4. **格式**：EXIF GPS → Decimal Degrees → Reverse Geocode → 中文地點名

---

## 🔧 待實現 / Known Issues

| 項目 | 位置 | 狀態 |
|------|------|------|
| EXIF location 讀取 | chat_screen.dart → `_extractExifLocation()` | ✅ 已完成 |
| Chat attach 圖片 | chat_screen.dart → camera/photo_library buttons | ✅ 已完成 |
| Chat save to receipts + items | chat_screen.dart → `_saveExpense()` | ✅ 已完成 |
| Reverse geocode (GPS → 地點名) | chat_screen.dart → `_reverseGeocode()` (Nominatim) | ✅ 已完成 |
| Chat → location fallback chain | chat_screen.dart (`_extractExifLocation` → `_loadDefaultLocation`) | ✅ 已完成 |
| Chat input → LLM via Edge Function | `chat-parser` edge function (chat-parser/index.ts) | ✅ 已完成 |
| Chat 2-stage classification | `chat-parser` → is_expense + completeness check | ✅ 已完成 |
| Prd categories dynamic read | edge function → DB (prd_categories, store_categories) | ✅ 已完成 |
| Prd category: `takeaway` | DB + edge function | ✅ 已完成 |
| Store categories: `restaurant`, `cafe` | DB + edge function | ✅ 已完成 |
| Row-reconstructed OCR format | receipt_scanner_service.dart → `_groupByRow()` | ✅ 已完成 |
| OCR item-price pairing | enhanced prompt + row grouping | ✅ 已完成 |
| user_profiles.default_location 更新 | — | ⬜ 待做 |
| Employer App (僱主版) | apps/employer_app/ | ✅ 已建立 (Receipts + My Code + Settings) |
| Rate limiting (app level) | chat_screen.dart | ⬜ 暫時不做 |

---

## 📝 修改記錄

| 日期 | 修改內容 |
|------|---------|
| 2026-05-15 | 加入 OCR + LLM workflow、Chat + Image workflow、Relation logic、Edge function |
| 2026-05-15 | 切換 LLM provider：Gemini → OpenRouter DeepSeek V4 (paid) |
| 2026-05-15 | 加入 receipt_items table（normalized item storage）|
| 2026-05-15 | 加入 short_code（6位僱主邀請碼）|
| 2026-05-15 | 加入 store_categories + prd_categories master tables |
| 2026-05-15 | 加入 `takeaway` prd_category |
| 2026-05-15 | 實現 OCR row grouping（item-price pairing）|
| 2026-05-15 | 重寫 chat-parser edge function（2-stage classification）|
| 2026-05-16 | chat-parser 取代 Gemini direct call（所有文字走 edge function）|