# Archived Packages

這些 package 結構已建立但代碼實際在 `apps/*/lib/core/services/` 中 implement，package folder 變成空殼。

## 移動記錄

| Date | Package | Reason |
|------|---------|--------|
| 2026-05-19 | ai-booking-agent | 代碼在 `helper_app/lib/core/services/ai_booking_agent_service.dart` |
| 2026-05-19 | receipt-scanner | 代碼在 `helper_app/lib/core/services/receipt_scanner_service.dart` |
| 2026-05-19 | price-alert-engine | 從未 implement，完全空殼 |

## 刪除條件

- 確認 `apps/helper_app/lib/core/services/` 中嘅代碼已完整覆蓋功能
- 確認冇任何 App 引用呢三個 package
- 預計：若 3 個月內冇相關 task，直接刪除

## 現存有用的 packages

- `receipt-parser` — ✅ helper_app 在用
- `localization` — ✅ helper_app + employer_app 在用