# MaidLedger: Unify Chat + Scan DB Write Flow + Fix All Issues

## Context

You are in `/home/joe-s-openclaw/.openclaw/agents/developer/agent/maidledger` on branch `feature/unified-schema-fix`. 

**Goal:** Make Chat and Scan write to **exactly the same tables** with **exactly the same schema**. Only input method differs (text vs camera).

## Critical: All 13 Issues Must Be Fixed

### 🔴 Issue 1: `ProductMatchingService.createMasterProduct` — Double `canonicalName` parameter
**File:** `apps/helper_app/lib/core/services/product_matching_service.dart`
**Problem:** Constructor has duplicate named parameters `canonicalName`, `brand`, `prdCate`.
**Fix:** Remove duplicate named parameters (keep one set only).

### 🔴 Issue 2: API key hardcoded in `ai_booking_agent_service.dart`
**File:** `apps/helper_app/lib/core/services/ai_booking_agent_service.dart`
**Problem:** `'Authorization': 'Bearer…90J0'` hardcoded.
**Fix:** Use `dotenv.env['SUPABASE_ANON_KEY']` or get from supabase client.

### 🔴 Issue 3: `price_history` written twice in `chat_screen._saveExpense`
**File:** `apps/helper_app/lib/features/chat/chat_screen.dart`
**Problem:** When `items.isNotEmpty`, `_matchProductsAndWritePriceHistory` is called inside the if-block AND again after it. Price history gets written TWICE.
**Fix:** Remove the second call (inside else block is fine for single-item case, but first call in if-block should cover all cases). Ensure price_history is written exactly ONCE per receipt.

### 🟡 Issue 4: `ShopMatchingService._ilikeMatch` — `textSearch` without try-catch
**File:** `apps/helper_app/lib/core/services/shop_matching_service.dart`
**Problem:** `textSearch()` query can throw unhandled exception.
**Fix:** Wrap the query in try-catch, fall back to ILIKE if textSearch fails.

### 🟡 Issue 5: Timeout detection too broad
**File:** `apps/helper_app/lib/features/chat/chat_screen.dart`
**Problem:** `e.toString().contains('timeout')` matches ANY error with "timeout" in message.
**Fix:** Use more specific detection like `e is TimeoutException` or check specific error messages.

### 🟡 Issue 6: `_uploadImage` fallback has no flag
**File:** `apps/helper_app/lib/features/chat/chat_screen.dart`
**Problem:** Fallback to base64 on storage failure with no indicator.
**Fix:** Track a flag `_imageUsedFallback` to indicate this happened.

### 🟠 Issue 7: `_buildItemsFromIntent` price extraction — uses first match, not max
**File:** `apps/helper_app/lib/features/chat/chat_screen.dart`
**Problem:** `regex.firstMatch()` returns first price, not the largest.
**Fix:** Collect all matches and return the max price.

### 🟠 Issue 8: Location picker "📍 手動選擇" returns null instead of opening picker
**File:** `apps/helper_app/lib/features/chat/chat_screen.dart`
**Problem:** The button just does `Navigator.pop(context, null)`.
**Fix:** Actually open the location picker dialog `_showLocationPickerDialog()`.

### 🟠 Issue 9: No network connectivity check
**File:** Both `chat_screen.dart` and `scan_screen.dart`
**Problem:** Direct HTTP calls without checking network first.
**Fix:** Use `connectivity_plus` package. Add `_checkConnectivity()` and call before edge function invocations. Show "無網絡連接" snackbar if offline.

### 🟠 Issue 10: `maidledger_localization` package potentially missing
**File:** `apps/helper_app/lib/main.dart`
**Problem:** Import exists but package might not be built.
**Fix:** Check if `packages/localization/` has actual code. If not, create a stub or remove the import.

### 🟠 Issue 11: Product matching duplicated in chat_screen vs scan_screen
**File:** `apps/helper_app/lib/features/scan/scan_screen.dart` (top-level function `_getMasterProductIdForItem`)
**Problem:** Two different implementations of product matching.
**Fix:** Use `ProductMatchingService` from `core/services/product_matching_service.dart` in scan_screen too.

### 🟠 Issue 12: Top-level functions outside class
**File:** `apps/helper_app/lib/features/scan/scan_screen.dart`
**Problem:** `_getMasterProductIdForItem()` and `_logAppError()` are top-level functions.
**Fix:** Move inside `ScanScreen` class as private methods.

### 🟠 Issue 13: ScanScreen processing error leaves stale preview state
**File:** `apps/helper_app/lib/features/scan/scan_screen.dart`
**Problem:** On error, `_scanPhase` set to `preview` but `_capturedImage` might be stale.
**Fix:** Clear captured image on error: `setState(() { _capturedImage = null; _scanPhase = ScanPhase.camera; })`.

## Unified DB Write Flow (Target Architecture)

Both Chat and Scan must write to these tables identically:

```
receipts          — store_name, store_cate, location, transaction_date, raw_text, amount, shop_id
receipt_items     — item_name (Chinese), item_raw_text, qty, unit_price, line_total, prd_cate, master_product_id
shops             — canonical_name, shop_type (created via ShopMatchingService if not exists)
shop_aliases      — raw_name → shop_id (created via ShopMatchingService)
master_products   — canonical_name, prd_cate (created via ProductMatchingService if not exists)
product_aliases   — raw_name → master_product_id (created via ProductMatchingService)
price_history     — master_product_id, shop_id, price, unit, source_receipt_id, source_type='receipt'
```

### Chat Screen `_saveExpense` flow:
1. INSERT receipts (with shop_id from ShopMatchingService)
2. INSERT receipt_items (with master_product_id to be bound later)
3. Run ShopMatchingService → bind shop_id to receipts
4. Run ProductMatchingService for each item → create master_product + alias if needed, bind master_product_id to receipt_items
5. INSERT price_history (ONE insert, not two)

### Scan Screen `_saveReceiptToDb` flow:
1. INSERT receipts (with shop_id from ShopMatchingService)
2. INSERT receipt_items
3. Same Phase 4 as Chat: Product matching + price_history write

**Both flows must be IDENTICAL for receipt_items, master_products, product_aliases, shops, shop_aliases, price_history.**

## Key Implementation Notes

- `chat_screen._saveExpense` has the bug where `_matchProductsAndWritePriceHistory` is called TWICE (once inside `if (items.isNotEmpty)` block, once after). Remove the second call.
- Scan screen should use `ProductMatchingService.matchItem()` for matching, not a separate top-level function.
- When matching creates a new master_product (returns `matchedVia.newProduct`), also insert into `product_aliases` with source='ocr'.
- price_history write should happen AFTER receipt_items are inserted so we have receipt_id for `source_receipt_id`.

## Process

1. Fix issues 1-13 in order
2. After fixing, review both `_saveExpense` (chat) and `_saveReceiptToDb` (scan) to ensure they write to identical tables
3. Make sure price_history is written EXACTLY ONCE per receipt entry
4. Run `flutter pub get` in both apps to check for compilation errors
5. Commit with message: `fix: resolve all 13 issues + unify chat/scan DB write flow`

## Notification

When complete, send message to user (channel: webchat) confirming all fixes and the unified write flow.