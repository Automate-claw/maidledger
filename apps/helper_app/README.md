# MaidLedger — Helper App

外傭 (FDW) 使用的 Flutter 應用。

## 📂 重要檔案

| 檔案 | 用途 |
|------|------|
| `lib/main.dart` | App 入口、AuthGate、RelationGate |
| `lib/features/scan/scan_screen.dart` | 📷 OCR 掃描 workflow |
| `lib/features/chat/chat_screen.dart` | 💬 AI Chat 記帳 workflow |
| `lib/features/history/history_screen.dart` | 📜 收據歷史 |
| `lib/features/auth/relation_gate.dart` | 🔗 僱主連接 logic |
| `lib/core/services/receipt_scanner_service.dart` | ML Kit OCR |
| `lib/core/services/ai_booking_agent_service.dart` | Chat input parser |
| `lib/core/services/relation_service.dart` | Relation check/link |

## 🔧 技術架構

- **State Management:** Riverpod
- **Backend:** Supabase
- **OCR:** Google ML Kit (On-device, Chinese)
- **LLM:** OpenRouter `deepseek/deepseek-v4-flash:free` (via Edge Function)

## 📖 詳細文檔

- [ARCHITECTURE.md](../../ARCHITECTURE.md) — 詳細 workflow、各層 logic、error handling
- [SPEC.md](../../SPEC.md) — 技術規格、DB schema、external dependencies

## 🚀 開發

```bash
cd apps/helper_app
flutter run
```

## 📷 Workflow 總覽

```
Scan Tab:
  Camera → Compress → EXIF GPS → Upload Storage → ML Kit OCR → Edge LLM → Save receipts + items

Chat Tab:
  Text Input → AIBookingAgent parse → (Optional Image) → EXIF GPS → Save receipts + items
```