// ══════════════════════════════════════════════════════════════════════════════
// chat-orchestrate — coordinator for chat-based expense entry
// Calls: chat-parser → receipt-writer → shop-manager → product-manager
//
// Input:  { text, user_id, location? }
// Output: { success, receipt_id, needs_review, errors }
//
// Shop is OPTIONAL for chat — user may not provide store name.
// Shop flow only runs if store_name is non-null.
// ══════════════════════════════════════════════════════════════════════════════
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "";

// Returns today's date in HK timezone (YYYY-MM-DD)
function hkDate(): string {
  const hk = new Date().toLocaleString("en-US", { timeZone: "Asia/Hong_Kong" });
  return new Date(hk).toISOString().split("T")[0];
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal function caller
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
// Process chat input — orchestrates all modules
// Returns { success, receipt_id, needs_review, errors }
// ─────────────────────────────────────────────────────────────────────────────
async function processChatInput(
  text: string,
  userId: string,
  location?: string,
  attachedImageBase64?: string,
): Promise<{ success: boolean; receipt_id: string | null; needs_review: boolean; errors: string[] }> {
  const allErrors: string[] = [];

  // ── Step 1: chat-parser ──────────────────────────────────────────────
  let parseResult: any = null;
  try {
    const r = await callFunction("chat-parser", { text, user_id: userId });
    // chat-parser has a different response format: raw result without {success, data} wrapper
    // It returns { is_expense, items[], total_amount, store_name, ... } directly
    const rawData = r.data;
    if (!r.ok || !rawData || rawData.error) {
      throw new Error(`chat-parser failed (${r.status}): ${JSON.stringify(rawData)}`);
    }
    // Detect non-expense and return early
    if (!rawData.is_expense) {
      return {
        success: true,
        receipt_id: null,
        needs_review: false,
        errors: [],
      };
    }
    if (rawData.completeness === "insufficient") {
      return {
        success: false,
        receipt_id: null,
        needs_review: false,
        errors: [`insufficient: ${rawData.reason ?? "不明原因"}`],
      };
    }
    parseResult = rawData;
  } catch (e) {
    allErrors.push(`chat-parser error: ${e}`);
    return { success: false, receipt_id: null, needs_review: false, errors: allErrors };
  }

  const { storeCodes, prdCodes } = await getValidCodes();
  const confidence = parseResult.parse_confidence ?? 0;
  const needsReview = confidence < 0.7;
  const items = parseResult.items ?? [];
  const totalAmount = parseResult.total_amount ?? null;

  // ── Step 2: receipt-writer: create/update receipt ───────────────────
  let receiptId: string | null = null;
  try {
    const r = await callFunction("receipt-writer", {
      action: "createFromChat",
      user_id: userId,
      raw_text: text,
      store_name: parseResult.store_name ?? null,
      store_cate: storeCodes.includes(parseResult.store_cate) ? parseResult.store_cate : "other",
      location: location ?? parseResult.location ?? null,
      amount: totalAmount,
      transaction_date: parseResult.transaction_date ?? hkDate(),
      ocr_raw_text: text,
      ocr_reconstructed: null,
      attached_image_base64: attachedImageBase64 ?? null,
    });
    if (!r.ok || !r.data?.success) {
      allErrors.push(`receipt-writer (createFromChat) failed: ${JSON.stringify(r.data)}`);
    } else {
      receiptId = r.data.receipt_id ?? null;
    }
  } catch (e) {
    allErrors.push(`receipt-writer exception: ${e}`);
  }

  if (!receiptId) {
    return { success: false, receipt_id: null, needs_review: false, errors: allErrors };
  }

  // ── Step 3: shop-manager: upsert shop (ONLY if store_name provided) ─
  let shopId: string | null = null;
  if (parseResult.store_name) {
    try {
      const r = await callFunction("shop-manager", {
        action: "upsert",
        raw_shop_name: parseResult.store_name,
        shop_type: parseResult.store_cate,
        location: location ?? parseResult.location ?? null,
      });
      if (r.ok && r.data?.success && r.data.shop_id) {
        shopId = r.data.shop_id;
      } else {
        allErrors.push(`shop-manager upsert warning: ${JSON.stringify(r.data)}`);
      }
    } catch (e) {
      allErrors.push(`shop-manager upsert warning: ${e}`);
    }

    // ── Step 4: receipt-writer: link shop (ONLY if shopId found) ────────
    if (shopId) {
      try {
        const r = await callFunction("receipt-writer", {
          action: "writeShopLink",
          receipt_id: receiptId,
          shop_id: shopId,
        });
        if (!r.ok || !r.data?.success) {
          allErrors.push(`receipt-writer (writeShopLink) warning: ${JSON.stringify(r.data)}`);
        }
      } catch (e) {
        allErrors.push(`receipt-writer (writeShopLink) warning: ${e}`);
      }
    }
  }

  // ── Step 5: receipt-writer: write items (chat format) ───────────────
  if (items.length > 0) {
    try {
      const r = await callFunction("receipt-writer", {
        action: "writeItemsFromChat",
        receipt_id: receiptId,
        items,
        validPrdCodes: prdCodes,
      });
      if (!r.ok || !r.data?.success) {
        allErrors.push(`receipt-writer (writeItems) warning: ${JSON.stringify(r.data)}`);
      }
    } catch (e) {
      allErrors.push(`receipt-writer (writeItems) warning: ${e}`);
    }

    // ── Step 6+7: product-manager upsert loop (each item isolated) ────
    for (const item of items) {
      try {
        const matchName = item.extracted_name || item.item_name || item.item_raw_text || item.item_name;
        if (!matchName) continue;

        const pmResult = await callFunction("product-manager", {
          action: "upsert",
          item_name: matchName,
          brand: item.extracted_brand ?? null,
          prd_cate: item.prd_cate || "other",
        });

        if (!pmResult.ok || !pmResult.data?.success || !pmResult.data?.master_product_id) {
          allErrors.push(`product-manager (upsert) warning for "${matchName}": ${JSON.stringify(pmResult.data)}`);
          continue;
        }

        const masterProductId = pmResult.data.master_product_id;

        // Bind product to receipt_item
        const itemLookupRes = await fetch(
          `${SUPABASE_URL}/rest/v1/receipt_items?select=id,master_product_id&receipt_id=eq.${receiptId}&item_name=eq.${encodeURIComponent(item.item_name ?? item.item_raw_text ?? "")}&order=id.desc&limit=1`,
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
        if (item.unit_price != null) {
          const phResult = await callFunction("receipt-writer", {
            action: "writePriceHistory",
            master_product_id: masterProductId,
            item,
            parse_result: parseResult,
            receipt_id: receiptId,
            shop_id: shopId,
          });
          if (!phResult.ok || !phResult.data?.success) {
            allErrors.push(`receipt-writer (writePriceHistory) warning for "${matchName}": ${JSON.stringify(phResult.data)}`);
          }
        }
      } catch (e) {
        // Per-item isolated — never affects other items
        allErrors.push(`product/price loop warning for item: ${e}`);
      }
    }
  }

  return {
    success: allErrors.filter((e) => e.includes("failed")).length === 0,
    receipt_id: receiptId,
    needs_review: needsReview,
    errors: allErrors,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// HTTP handler
// ─────────────────────────────────────────────────────────────────────────────
serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    let body: any = {};
    try { body = await req.json(); } catch {}

    const text = body.text ?? "";
    const userId = body.user_id ?? "anonymous";
    const location = body.location ?? undefined;
    const attachedImageBase64 = body.attached_image_base64 ?? undefined;

    if (!text.trim()) {
      return new Response(JSON.stringify({ error: "text is required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const result = await processChatInput(text, userId, location, attachedImageBase64);

    return new Response(JSON.stringify(result), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (error) {
    console.error("chat-orchestrate error:", error);
    return new Response(JSON.stringify({ success: false, error: error.message ?? "Internal error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});