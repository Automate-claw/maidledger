# MaidLedger — 待修問題追蹤

> ⚠️ **規矩**：所有問題追蹤喺呢度，唔寫入 ARCHITECTURE.md。
> 更新後立即 commit，唔累積。

---

## 🔴 緊急（編譯失敗 / 安全風險）

| # | 位置 | 問題 | 狀態 | 備註 |
|---|---|---|---|---|
| 1 | `apps/helper_app/lib/core/services/product_matching_service.dart` | `createMasterProduct` 雙重 canonicalName 導致編譯失敗 | 🟡 待修 | — |
| 2 | `apps/helper_app/lib/core/services/ai_booking_agent_service.dart` | API key hardcoded | 🟡 待修 | — |

---

## 🟡 中等（運行時風險 / 邏輯問題）

| # | 位置 | 問題 | 狀態 | 備註 |
|---|---|---|---|---|
| 3 | `apps/helper_app/lib/features/chat/chat_screen.dart` | `_saveExpense` 中 `price_history` 寫兩次 | 🟡 待修 | — |
| 4 | `supabase/functions/shop-manager/index.ts` | `textSearch` 無 catch，可能 crash | 🟡 待修 | — |
| 5 | `supabase/functions/receipt-orchestrate/index.ts` | `timeout` 判斷太闊，race condition | 🟡 待修 | — |
| 6 | `_buildItemsFromIntent` | 只取第一個 price（應取最大） | 🟡 待修 | — |

---

## 📋 Phase 2 / 未來功能

| # | 功能 | 說明 | 優先級 |
|---|---|---|---|
| 7 | 防重複 Scan 審批機制 | 規則：>3日舊單、7日內相同金額+items 需審批 | 🟡 Phase 2 |

---

## 📋 修復記錄

| 日期 | # | 問題 | 修復方式 |
|---|---|---|---|
| 2026-05-25 | 1-6 全部 | 從 ARCHITECTURE.md 遷移到 TODO.md | 獨立追蹤文件 |
| 2026-05-26 | 7 | 防重複 Scan 審批機制 | MVP 暫緩，列入 Phase 2 |

---

*最後更新：2026-05-26*