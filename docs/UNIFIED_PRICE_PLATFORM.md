# MaidLedger Unified Price Platform Plan

**Date:** 2026-05-22
**Status:** Draft - Pending Implementation
**Goal:** Enable cross-source price comparison between scraper data and helper receipt records

---

## Problem Statement

Currently two separate price data systems that CANNOT compare:

| Source | Writes To | Canonical? |
|--------|-----------|------------|
| Scraper | `price_data` | ❌ Raw product names, raw shop names |
| Helper (receipt) | `price_history` | ✅ `master_product_id` + `shop_id` |

**Result:** price-alert-engine cannot compare helper purchases against scraper data because they reference different product/shop entities.

---

## Target Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    UNIFIED PRICE PLATFORM                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌──────────────┐         ┌──────────────┐                     │
│   │   Scraper   │         │ Helper App   │                     │
│   │  (Python)   │         │  (Receipt)   │                     │
│   └──────┬───────┘         └──────┬───────┘                    │
│          │                         │                            │
│          ▼                         ▼                            │
│   ┌──────────────────────────────────────────┐                  │
│   │         SHOP MATCHING SERVICE            │                  │
│   │  "惠康" → shops.id                       │                  │
│   │  "百佳" → shops.id                       │                  │
│   └──────────────────┬───────────────────────┘                  │
│                      │                                          │
│                      ▼                                          │
│   ┌──────────────────────────────────────────┐                  │
│   │       PRODUCT MATCHING SERVICE           │                  │
│   │  "急凍紅衫魚 400g" → master_products.id   │                  │
│   │  "鯛魚" → master_products.id            │                  │
│   └──────────────────┬───────────────────────┘                  │
│                      │                                          │
│                      ▼                                          │
│   ┌──────────────────────────────────────────┐                  │
│   │           price_history                  │                  │
│   │  (master_product_id + shop_id + price)   │                  │
│   └──────────────────┬───────────────────────┘                  │
│                      │                                          │
│                      ▼                                          │
│   ┌──────────────────────────────────────────┐                  │
│   │         price-alert-engine               │                  │
│   │  Compare: helper price vs HK avg         │                  │
│   └──────────────────────────────────────────┘                  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Implementation Steps

### Phase 1: Database Migration

**File:** `supabase/migrations/022_unified_price_history.sql`

```sql
-- 1. Add source_type to distinguish scraper vs receipt origins
ALTER TABLE public.price_history 
  ADD COLUMN IF NOT EXISTS source_type TEXT 
  DEFAULT 'receipt'
  CHECK (source_type IN ('receipt', 'scraper'));

-- 2. Mark existing receipt data
UPDATE price_history SET source_type = 'receipt' WHERE source_type IS NULL;

-- 3. Keep price_data as raw cache (don't delete yet, for migration safety)
-- Eventually deprecate in favor of direct price_history writes
```

### Phase 2: Scraper Rewrite

**Goal:** Scraper writes canonical data directly to `price_history`

Key changes to `services/scraper/src/scraper.py`:

1. **Shop Matching** — Resolve raw supermarket name → `shops.id`
   ```python
   async def match_shop(self, raw_name: str) -> UUID:
       # Try existing alias first
       shop_id = await self.db.fetchval(
           """SELECT shop_id FROM shop_aliases WHERE raw_name = $1""",
           raw_name
       )
       if shop_id:
           return shop_id
       # Create new canonical shop + alias
       shop_id = await self.db.fetchval("""
           INSERT INTO shops (canonical_name, shop_type) 
           VALUES ($1, 'supermarket') RETURNING id
       """, raw_name)
       await self.db.execute(
           """INSERT INTO shop_aliases (raw_name, shop_id, source) VALUES ($1, $2, 'crawler')""",
           raw_name, shop_id
       )
       return shop_id
   ```

2. **Product Matching** — Resolve raw product name → `master_products.id`
   ```python
   async def match_product(self, raw_name: str, category: str) -> UUID:
       # ILIKE match on master_products.canonical_name or search_keywords
       product_id = await self.db.fetchval("""
           SELECT id FROM master_products 
           WHERE prd_cate = $1 
           AND (canonical_name ILIKE $2 OR $2 ILIKE '%' || canonical_name || '%')
           LIMIT 1
       """, category, f"%{raw_name}%")
       if not product_id:
           # Create new master product
           product_id = await self.db.fetchval("""
               INSERT INTO master_products (canonical_name, prd_cate, search_keywords)
               VALUES ($1, $2, ARRAY[$1]) RETURNING id
           """, raw_name, category)
           await self.db.execute(
               """INSERT INTO product_aliases (raw_name, master_product_id, source) 
                  VALUES ($1, $2, 'crawler')""",
               raw_name, product_id
           )
       return product_id
   ```

3. **Write to price_history**
   ```python
   async def save_canonical_price(self, product_id, shop_id, price, unit, location):
       await self.db.execute("""
           INSERT INTO price_history 
               (master_product_id, shop_id, location, region, price, unit, source_type, recorded_at)
           VALUES ($1, $2, $3, $4, $5, $6, 'scraper', CURRENT_DATE)
           ON CONFLICT (master_product_id, shop_id, recorded_at)
           DO UPDATE SET price = EXCLUDED.price, unit = EXCLUDED.unit
       """, product_id, shop_id, location, region, price, unit)
   ```

### Phase 3: price-alert-engine Enhancement

Update alert logic to use unified `price_history`:

```typescript
const { data: stats } = await supabase.rpc('get_price_stats', {
  p_product_id: master_product_id,
  p_days: 7
});

// stats.avg_price, stats.min_price, stats.max_price
// Now works for BOTH scraper AND receipt data
```

Add new RPC function:
```sql
CREATE OR REPLACE FUNCTION get_price_stats(
  p_product_id UUID,
  p_days INTEGER DEFAULT 7
) RETURNS JSONB AS $$
DECLARE
  result JSONB;
BEGIN
  SELECT jsonb_build_object(
    'avg_price', ROUND(AVG(price)::numeric, 2),
    'min_price', MIN(price),
    'max_price', MAX(price),
    'count', COUNT(*),
    'sources', ARRAY_AGG(DISTINCT source_type)
  ) INTO result
  FROM price_history
  WHERE master_product_id = p_product_id
    AND recorded_at > CURRENT_DATE - p_days;
  
  RETURN COALESCE(result, '{}'::jsonb);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

---

## Data Flow Summary

| Step | Scraper | Helper |
|------|---------|--------|
| 1 | Crawl raw HTML | Scan receipt / Chat input |
| 2 | Parse product + price | Parse via LLM |
| 3 | **Shop matching** → `shops.id` | **Shop matching** → `shops.id` |
| 4 | **Product matching** → `master_products.id` | **Product matching** → `master_products.id` |
| 5 | Write `price_history (source_type='scraper')` | Write `price_history (source_type='receipt')` |
| 6 | — | Link to `receipts.id` via `source_receipt_id` |
| 7 | Alert engine compares all sources | Alert engine compares all sources |

---

## Migration Notes

- `price_data` table to be deprecated (keep for 1 month for audit)
- All new writes go to `price_history`
- Existing `price_data` records can be migrated via one-time batch script:
  ```python
  # Migrate old price_data to price_history
  for row in price_data.where(scraped_at > '2026-01-01'):
      shop_id = match_shop(row.supermarket)
      product_id = match_product(row.product_name, row.category)
      price_history.insert(
          master_product_id=product_id,
          shop_id=shop_id,
          price=row.price,
          unit=row.unit,
          recorded_at=row.scraped_at.date(),
          source_type='scraper'
      )
  ```

---

## Status

- [x] Architecture documented
- [ ] Migration 022 created
- [ ] Scraper shop matching implemented
- [ ] Scraper product matching implemented
- [ ] Scraper writes to price_history
- [ ] price-alert-engine updated
- [ ] price_data deprecated
- [ ] Migration script for existing data