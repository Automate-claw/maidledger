// ══════════════════════════════════════════════════════════════════════════════
// receipt-orchestrate — coordinator for receipt processing
// Calls: receipt-parse → shop-manager → product-manager → receipt-writer
//
// Modes:
//   webhook : POST { receipt_id }  → process one receipt immediately
//   cron    : GET                   → batch process stale pending receipts
//
// Error handling: each step is isolated — one failure does NOT block others.
// Each item's product matching is also isolated in its own try/catch.
// ══════════════════════════════════════════════════════════════════════════════
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const FALLBACK_MIN_AGE_SEC = 120;
const HIGH_AMOUNT_THRESHOLD = 500;

// ─────────────────────────────────────────────────────────────────────────────
// Internal function caller (same project → internal REST call)
// ─────────────────────────────────────────────────────────────────────────────
async function callFunction(funcName: string, payload: any): Promise<any> {
  const resp = await fetch(`${SUPABASE_URL}/functions/v1/${funcName}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${SUPABASE_SERVICE_KEY}`,
    },
    body: JSON.stringify(payload),
  });
  const data = await resp.json();
  return { ok: resp.ok, status: resp.status, data };
}

// ─────────────────────────────────────────────────────────────────────────────
// Categories helper (local, no external call)
// ─────────────────────────────────────────────────────────────────────────────
let categoriesCache: { storeCategories: any[]; prdCategories: any[]; fetchedAt: number } | null = null;

async function getValidCodes() {
  if (categoriesCache && Date.now() - categoriesCache.fetchedAt < 5 * 60 * 1000) {
    return {
      storeCodes: categoriesCache.storeCategories.map((c: any) => c.code),
      prdCodes: categoriesCache.prdCategories.map((c: any) => c.code),
    };
  }
  const [storeRes, prdRes] = await Promise.all([
    fetch(`${SUPABASE_URL}/rest/v1/store_categories?select=code`, {
      headers: { apikey: SUPABASE_SERVICE_KEY, Authorization: `Bearer ${SUPABASE_SERVICE_KEY}` },
    }),
    fetch(`${SUPABASE_URL}/rest/v1/prd_categories?select=code`, {
      headers: { apikey: SUPABASE_SERVICE_KEY, Authorization: `Bearer ${SUPABASE_SERVICE_KEY}` },
    }),
  ]);
  const storeCategories = await storeRes.json();
  const prdCategories = await prdRes.json();
  categoriesCache = { storeCategories, prdCategories, fetchedAt: Date.now() };
  return {
    storeCodes: storeCategories.map((c: any) => c.code),
    prdCodes: prdCategories.map((c: any) => c.code),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Atomic lock — only process if receipt still in pending state
// ─────────────────────────────────────────────────────────────────────────────
async function lockReceipt(receiptId: string): Promise<boolean> {
  const lockResp = await fetch(
    `${SUPABASE_URL}/rest/v1/receipts?id=eq.${receiptId}&parse_status=eq.pending&select=id,ocr_raw_text,ocr_reconstructed,raw_text`,
    {
      method: "PATCH",
      headers: {
        apikey: SUPABASE_SERVICE_KEY,
        Authorization: `Bearer ${SUPABASE_SERVICE_KEY}`,
        "Content-Type": "application/json",
        Prefer: "return=representation",
      },
      body: JSON.stringify({ parse_status: "processing" }),
    }
  );
  if (!lockResp.ok) return false;
  const locked = await lockResp.json();
  return locked && locked.length > 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Process one receipt — orchestrates all module functions
// Returns { success, receipt_id, needs_review, errors }
// ─────────────────────────────────────────────────────────────────────────────
async function processReceipt(receiptId: string): Promise<{ success: boolean; receipt_id: string; needs_review: boolean; errors: string[] }> {
  const allErrors: string[] = [];

  // Step 0: Lock receipt
  const locked = await lockReceipt(receiptId);
  if (!locked) {
    console.log(`Receipt ${receiptId} skipped (not pending or already locked)`);
    return { success: false, receipt_id: receiptId, needs_review: false, errors: ["skipped: not pending or already locked"] };
  }

  // Fetch raw text and image URL
  const receiptRes = await fetch(`${SUPABASE_URL}/rest/v1/receipts?id=eq.${receiptId}&select=ocr_raw_text,ocr_reconstructed,raw_text,image_local_path,image_url`, {
    headers: { apikey: SUPABASE_SERVICE_KEY, Authorization: `Bearer ${SUPABASE_SERVICE_KEY}` },
  });
  const receiptData = await receiptRes.json();
  const receipt = receiptData[0];
  if (!receipt) {
    allErrors.push("receipt not found after lock");
    return { success: false, receipt_id: receiptId, needs_review: false, errors: allErrors };
  }

  // ── Step 1: receipt-vision (pure LLM Vision, replaces ML Kit + LLM) ──
  let parseResult: any = null;
  try {
    // Use image_url from the receipt's stored image
    const imageUrl = receipt.image_local_path || receipt.image_url;
    const parseResult_ = await callFunction("receipt-vision", {
      image_url: imageUrl,
    });
    if (!parseResult_.ok || !parseResult_.data?.success) {
      throw new Error(`receipt-vision failed (${parseResult_.status}): ${JSON.stringify(parseResult_.data)}`);
    }
    parseResult = parseResult_.data.data;
    console.log(`[receipt-orchestrate] receipt-vision tokens: ${JSON.stringify(parseResult_.data.tokens_used)}`);
  } catch (e) {
    allErrors.push(`receipt-vision error: ${e}`);
    // Mark as failed
    await fetch(`${SUPABASE_URL}/rest/v1/receipts?id=eq.${receiptId}`, {
      method: "PATCH",
      headers: { apikey: SUPABASE_SERVICE_KEY, Authorization: `Bearer ${SUPABASE_SERVICE_KEY}`, "Content-Type": "application/json" },
      body: JSON.stringify({ parse_status: "failed" }),
    });
    return { success: false, receipt_id: receiptId, needs_review: false, errors: allErrors };
  }

  const { storeCodes, prdCodes } = await getValidCodes();
  const confidence = parseResult.parse_confidence ?? 0;
  const needsReview = confidence < 0.7 || (parseResult.total_amount ?? 0) > HIGH_AMOUNT_THRESHOLD;

  // ── Step 2: receipt-writer: update receipt metadata ───────────────────
  try {
    const r = await callFunction("receipt-writer", {
      action: "writeReceipt",
      receipt_id: receiptId,
      parse_result: parseResult,
      validPrdCodes: prdCodes,
      validStoreCodes: storeCodes,
    });
    if (!r.ok || !r.data?.success) {
      allErrors.push(`receipt-writer (writeReceipt) failed: ${JSON.stringify(r.data)}`);
    }
  } catch (e) {
    allErrors.push(`receipt-writer (writeReceipt) exception: ${e}`);
  }

  // ── Step 3: shop-manager: upsert shop ──────────────────────────────────
  let shopId: string | null = null;
  if (parseResult.store_name) {
    try {
      const r = await callFunction("shop-manager", {
        action: "upsert",
        raw_shop_name: parseResult.store_name,
        shop_type: parseResult.store_cate,
        location: parseResult.location,
      });
      if (r.ok && r.data?.success && r.data.shop_id) {
        shopId = r.data.shop_id;
      } else {
        allErrors.push(`shop-manager upsert failed: ${JSON.stringify(r.data)}`);
      }
    } catch (e) {
      allErrors.push(`shop-manager upsert exception: ${e}`);
    }

    // ── Step 4: receipt-writer: link shop ──────────────────────────────
    if (shopId) {
      try {
        const r = await callFunction("receipt-writer", {
          action: "writeShopLink",
          receipt_id: receiptId,
          shop_id: shopId,
        });
        if (!r.ok || !r.data?.success) {
          allErrors.push(`receipt-writer (writeShopLink) failed: ${JSON.stringify(r.data)}`);
        }
      } catch (e) {
        allErrors.push(`receipt-writer (writeShopLink) exception: ${e}`);
      }
    }
  }

  // ── Step 5: receipt-writer: write items ───────────────────────────────
  const items = parseResult.items ?? [];
  if (items.length > 0) {
    try {
      const r = await callFunction("receipt-writer", {
        action: "writeItems",
        receipt_id: receiptId,
        items,
        validPrdCodes: prdCodes,
      });
      if (!r.ok || !r.data?.success) {
        allErrors.push(`receipt-writer (writeItems) failed: ${JSON.stringify(r.data)}`);
      }
    } catch (e) {
      allErrors.push(`receipt-writer (writeItems) exception: ${e}`);
    }

    // ── Step 6+7: product matching loop (each item isolated) ────────────
    for (const item of items) {
      try {
        const matchName = item.extracted_name || item.item_name;

        // product-manager upsert: match OR create
        const pmResult = await callFunction("product-manager", {
          action: "upsert",
          item_name: matchName,
          brand: item.extracted_brand ?? null,
          prd_cate: item.prd_cate || "other",
        });

        if (!pmResult.ok || !pmResult.data?.success || !pmResult.data?.master_product_id) {
          const errMsg = pmResult.data?.error ?? JSON.stringify(pmResult.data);
          allErrors.push(`product-manager (upsert) error for "${matchName}": ${errMsg}`);
          continue;
        }

        const masterProductId = pmResult.data.master_product_id;

        // Bind product to receipt_item
        // Use item_name (original raw name) to find the inserted row
        const itemLookupRes = await fetch(
          `${SUPABASE_URL}/rest/v1/receipt_items?select=id,master_product_id&receipt_id=eq.${receiptId}&item_name=eq.${encodeURIComponent(item.item_name)}&order=id.desc&limit=1`,
          { headers: { apikey: SUPABASE_SERVICE_KEY, Authorization: `Bearer ${SUPABASE_SERVICE_KEY}` } }
        );
        const itemRows2 = await itemLookupRes.json();
        const targetItem = itemRows2?.[0];
        if (targetItem && !targetItem.master_product_id) {
          await fetch(`${SUPABASE_URL}/rest/v1/receipt_items?id=eq.${targetItem.id}`, {
            method: "PATCH",
            headers: { apikey: SUPABASE_SERVICE_KEY, Authorization: `Bearer ${SUPABASE_SERVICE_KEY}`, "Content-Type": "application/json" },
            body: JSON.stringify({ master_product_id: masterProductId }),
          });
        }

        // receipt-writer: write price_history
        const phResult = await callFunction("receipt-writer", {
          action: "writePriceHistory",
          master_product_id: masterProductId,
          item,
          parse_result: parseResult,
          receipt_id: receiptId,
          shop_id: shopId,
        });
        if (!phResult.ok || !phResult.data?.success) {
          allErrors.push(`receipt-writer (writePriceHistory) error for item "${matchName}": ${JSON.stringify(phResult.data)}`);
        }
      } catch (e) {
        // Per-item isolated error — never affects other items
        allErrors.push(`product match/price loop error for "${item.item_name ?? item.item_name}": ${e}`);
      }
    }
  }

  const finalSuccess = allErrors.length === 0;
  console.log(`Receipt ${receiptId} processed. success=${finalSuccess}, needs_review=${needsReview}, errors=${allErrors.length}`);
  return { success: finalSuccess, receipt_id: receiptId, needs_review: needsReview, errors: allErrors };
}

// ─────────────────────────────────────────────────────────────────────────────
// HTTP handler
// ─────────────────────────────────────────────────────────────────────────────
serve(async (req) => {
  if (req.method === "GET" && new URL(req.url).pathname.endsWith("health")) {
    return new Response(JSON.stringify({ status: "ok", timestamp: Date.now() }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    // ── WEBHOOK MODE ──────────────────────────────────────────────────────
    let body: any = {};
    try { body = await req.json(); } catch {}
    if (body?.receipt_id) {
      const result = await processReceipt(body.receipt_id);
      return new Response(JSON.stringify({ mode: "webhook", ...result }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ── CRON MODE ───────────────────────────────────────────────────────
    const minAgeDate = new Date(Date.now() - FALLBACK_MIN_AGE_SEC * 1000).toISOString();
    const resp = await fetch(
      `${SUPABASE_URL}/rest/v1/receipts?select=id&parse_status=eq.pending&created_at=lt.${encodeURIComponent(minAgeDate)}&limit=5`,
      { headers: { apikey: SUPABASE_SERVICE_KEY, Authorization: `Bearer ${SUPABASE_SERVICE_KEY}` } }
    );
    if (!resp.ok) {
      return new Response(JSON.stringify({ error: "DB query failed", details: await resp.text() }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const pending = await resp.json();
    if (pending.length === 0) {
      return new Response(JSON.stringify({ mode: "cron", processed: 0, message: "No stale pending receipts" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    let processed = 0;
    for (const row of pending) {
      try {
        const result = await processReceipt(row.id);
        if (result.success) processed++;
      } catch (e) {
        console.error(`Cron error processing receipt ${row.id}:`, e);
      }
    }

    return new Response(JSON.stringify({ mode: "cron", processed, total: pending.length }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (error) {
    console.error("receipt-orchestrate error:", error);
    return new Response(JSON.stringify({ error: error.message ?? "Internal error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});