# MaidLedger — 待修問題追蹤

> ⚠️ **規矩**：所有問題追蹤喺呢度，唔寫入 ARCHITECTURE.md。
> 更新後立即 commit，唔累積。

---

## 🔴 緊急（編譯失敗 / 安全風險）

| # | 位置 | 問題 | 狀態 | 備註 |
|---|---|---|---|---|
| 1 | `apps/helper_app/lib/core/services/product_matching_service.dart` | `createMasterProduct` 雙重 canonicalName 導致編譯失敗 | ✅ 已修（2026-05-29） | — |
| 2 | `apps/helper_app/lib/core/services/ai_booking_agent_service.dart` | API key hardcoded | ✅ 已修（2026-05-29） | — |

---

## 🟡 中等（運行時風險 / 邏輯問題）

| # | 位置 | 問題 | 狀態 | 備註 |
|---|---|---|---|---|
| 3 | `apps/helper_app/lib/features/chat/chat_screen.dart` | `_saveExpense` 中 `price_history` 寫兩次 | ✅ 已修（2026-05-29） | — |
| 4 | `supabase/functions/shop-manager/index.ts` | `textSearch` 無 catch，可能 crash | ✅ 已修（2026-05-29） | — |
| 5 | `supabase/functions/receipt-orchestrate/index.ts` | `timeout` 判斷太闊，race condition | ✅ 已修（2026-05-29） | — |
| 6 | `_buildItemsFromIntent` | 只取第一個 price（應取最大） | ✅ 已修（2026-05-29） | — |

---

## 📋 Phase 2 / 未來功能

| # | 功能 | 說明 | 優先級 |
|---|---|---|---|
| 7 | 防重複 Scan 審批機制 | ✅ Rule 1: >3日舊單 → needs_review<br>✅ Rule 2: 3日內同 store_cate+amount+items → needs_review<br>❌ 僱主通知 + 審批 UI 未實作 | 🟡 Phase 2 (部分完成) |

---

## 📋 已完成功能

| # | 功能 | 日期 | 備註 |
|---|---|---|---|
| G1 | Chat 相片附件（Gallery/Camera → base64） | 2026-05-30 | ✅ 已實現（dev 分支） |
| G2 | Chat EXIF GPS 讀取 → district/region | 2026-05-30 | ✅ 已實現（dev 分支） |
| Trigger Fix | DB Trigger 加 parse_status="pending" condition | 2026-05-30 | ✅ 已修復（chat receipt 不再重觸 vision） |

---

## 📋 修復記錄

| 日期 | # | 問題 | 修復方式 |
|---|---|---|---|
| 2026-05-25 | 1-6 全部 | 從 ARCHITECTURE.md 遷移到 TODO.md | 獨立追蹤文件 |
| 2026-05-26 | 7 | 防重複 Scan 審批機制 | MVP 暫緩，列入 Phase 2 |
| 2026-05-29 | 1-6 全部 | 所有緊急/中等 BUG | ✅ 已全部修復 |
| 2026-05-29 | 7 | 防重複 Scan 審批機制 | ✅ 已實作 Rule 1 + Rule 2，❌ 僱主通知未實作 |
| 2026-05-30 | Trigger | Chat receipt 重复触发 receipt-vision | ✅ DB Trigger 加 WHEN parse_status="pending" condition |
| 2026-05-30 | G1/G2 | Chat 相片附件 + EXIF GPS | ✅ 已實現（架構完成，細節優化待定） |

---

*最後更新：2026-05-30*