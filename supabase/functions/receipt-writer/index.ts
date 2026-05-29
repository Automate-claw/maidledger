// ══════════════════════════════════════════════════════════════════════════════
// receipt-writer — writes parsed receipt data to DB
// Handles: receipt update, receipt_items, price_history, shop link
//
// Actions:
//   writeReceipt     : { action:"writeReceipt", receipt_id, parse_result, validPrdCodes }
//   writeItems       : { action:"writeItems", receipt_id, items[], validPrdCodes }
//   writePriceHistory: { action:"writePriceHistory", master_product_id, item, parse_result, receipt_id, shop_id? }
//   writeShopLink    : { action:"writeShopLink", receipt_id, shop_id }
// ══════════════════════════════════════════════════════════════════════════════
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────
async function rpcUpdateReceiptShop(supabaseUrl: string, supabaseKey: string, receiptId: string, shopId: string): Promise<boolean> {
  const rpcResp = await fetch(`${supabaseUrl}/rest/v1/rpc/update_receipt_shop`, {
    method: "POST",
    headers: {
      apikey: supabaseKey,
      Authorization: `Bearer ${supabaseKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ p_receipt_id: receiptId, p_shop_id: shopId }),
  });
  return rpcResp.ok;
}

// ─────────────────────────────────────────────────────────────────────────────
// Anti-cheat: check if receipt needs review (Rule 1: > 3 days, Rule 2: duplicate)
// Returns { needs_review, similar_receipts }
async function checkAntiCheat(
  supabaseUrl: string,
  supabaseKey: string,
  helperId: string,
  transactionDate: string,
  storeCate: string,
  amount: number,
  itemNames: string[],
  excludeReceiptId?: string,
): Promise<{ needs_review: boolean; similar_receipts: any[] }> {
  const threeDaysAgo = new Date();
  threeDaysAgo.setDate(threeDaysAgo.getDate() - 3);
  const threeDaysAgoStr = threeDaysAgo.toISOString().split('T')[0];

  let needsReview = false;
  const similarReceipts: any[] = [];

  // Rule 1: transaction_date > 3 days ago → needs review
  if (transactionDate < threeDaysAgoStr) {
    needsReview = true;
    console.log(`[checkAntiCheat] Rule 1 triggered: tx_date=${transactionDate} < 3 days ago`);
  }

  // Rule 2: within 3 days, same store_cate + amount + items → needs review
  // Query recent receipts (within 3 days)
  let queryUrl = `${supabaseUrl}/rest/v1/receipts?select=id,transaction_date,store_cate,amount,store_name&helper_id=eq.${helperId}&transaction_date=gte.${threeDaysAgoStr}&transaction_date=lt.${new Date().toISOString().split('T')[0]}`;
  if (excludeReceiptId) {
    queryUrl += `&id=not.eq.${excludeReceiptId}`;
  }

  try {
    const recentRes = await fetch(queryUrl, {
      headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` },
    });
    const recentReceipts = await recentRes.json();
    console.log(`[checkAntiCheat] found ${recentReceipts?.length ?? 0} recent receipts`);

    for (const rec of recentReceipts ?? []) {
      // Must have same store_cate and amount
      if (rec.store_cate !== storeCate || Number(rec.amount) !== amount) continue;

      // Fetch items for this receipt
      const itemsRes = await fetch(
        `${supabaseUrl}/rest/v1/receipt_items?select=item_name,unit_price&receipt_id=eq.${rec.id}`,
        { headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` } }
      );
      const items: any[] = await itemsRes.json();
      const existingItemNames = items.map(i => i.item_name).sort().join('|');
      const newItemNamesSorted = [...itemNames].sort().join('|');

      // Rule 2: ALL items must be exactly the same
      if (existingItemNames === newItemNamesSorted && newItemNamesSorted.length > 0) {
        console.log(`[checkAntiCheat] Rule 2 triggered: duplicate found rec_id=${rec.id}`);
        needsReview = true;
        similarReceipts.push({
          id: rec.id,
          transaction_date: rec.transaction_date,
          store_cate: rec.store_cate,
          amount: rec.amount,
          store_name: rec.store_name,
          items: items.map(i => ({ item_name: i.item_name, unit_price: i.unit_price })),
        });
      }
    }
  } catch (e) {
    console.error("[checkAntiCheat] Rule 2 check failed:", e);
  }

  return { needs_review: needsReview, similar_receipts: similarReceipts };
}

// ─────────────────────────────────────────────────────────────────────────────
serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "";

    let body: any;
    try { body = await req.json(); } catch { body = {}; }

    const action = body.action;
    const errors: string[] = [];

    // ── writeShopLink ──────────────────────────────────────────────────────
    if (action === "writeShopLink") {
      if (!body.receipt_id || !body.shop_id) {
        return new Response(JSON.stringify({ error: "receipt_id and shop_id required" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      try {
        const ok = await rpcUpdateReceiptShop(supabaseUrl, supabaseKey, body.receipt_id, body.shop_id);
        if (!ok) throw new Error("RPC returned non-ok");
        return new Response(JSON.stringify({ success: true }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      } catch (e) {
        return new Response(JSON.stringify({ success: false, error: String(e) }), {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    }

    // ── createFromChat ───────────────────────────────────────────────────
    // Creates a new receipt from chat input.
    // Looks up employer relation to get employer_id, then inserts receipt.
    if (action === "createFromChat") {
      if (!body.user_id || !body.raw_text) {
        return new Response(JSON.stringify({ error: "user_id and raw_text required" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      // Look up user's employer relationship to get employer_id (optional — helper may not have linked employer)
      let employerId: string | null = null;
      let relationId: string | null = null;
      try {
        const helperRes = await fetch(
          `${supabaseUrl}/rest/v1/employer_helper_relations?select=id,employer_id&helper_id=eq.${body.user_id}&status=eq.active&limit=1`,
          { headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` } }
        );
        const helperRelations = await helperRes.json();
        const relation = helperRelations?.[0];
        employerId = relation?.employer_id ?? null;
        relationId = relation?.id ?? null;
      } catch (e) {
        // Relation lookup failed — continue without employer link (helper may be unlinked)
      }

      // ── Anti-cheat check (Rule 1 & Rule 2) ───────────────────────────────
      const items: any[] = body.items ?? [];
      const itemNames = items.map((i: any) => i.item_name ?? i.item_raw_text ?? "").filter(Boolean);
      const { needs_review: antiCheatReview, similar_receipts } = await checkAntiCheat(
        supabaseUrl,
        supabaseKey,
        body.user_id,
        body.transaction_date ?? "",
        body.store_cate ?? "other",
        body.amount ?? 0,
        itemNames,
      );
      console.log(`[createFromChat] anti-cheat: needs_review=${antiCheatReview}, similar_count=${similar_receipts.length}`);

      const receiptRes = await fetch(`${supabaseUrl}/rest/v1/receipts`, {
        method: "POST",
        headers: {
          apikey: supabaseKey,
          Authorization: `Bearer ${supabaseKey}`,
          "Content-Type": "application/json",
          Prefer: "return=representation",
        },
        body: JSON.stringify({
          employer_id: employerId,
          helper_id: body.user_id,
          relation_id: relationId,
          raw_text: body.raw_text,
          ocr_raw_text: body.ocr_raw_text ?? null,
          ocr_reconstructed: body.ocr_reconstructed ?? null,
          location: body.location ?? null,
          amount: body.amount ?? null,
          transaction_date: body.transaction_date ?? null,
          store_name: body.store_name ?? "未知商戶",
          store_cate: body.store_cate ?? "other",
          parse_status: "parsed",
          parse_confidence: 0.8,
          needs_review: antiCheatReview,
          local_timestamp: Math.floor(Date.now() / 1000),
        }),
      });

      if (!receiptRes.ok) {
        const err = await receiptRes.text();
        return new Response(JSON.stringify({ success: false, error: `receipt insert failed (${receiptRes.status}): ${err}` }), {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const inserted = await receiptRes.json();
      const receiptId = inserted[0]?.id ?? inserted?.id;
      if (!receiptId) {
        return new Response(JSON.stringify({ success: false, error: "receipt insert returned no id" }), {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      // Upload image to storage, then include public URL directly in INSERT body
      if (body.attached_image_base64) {
        const imgBuf = Uint8Array.from(atob(body.attached_image_base64), c => c.charCodeAt(0));
        const ext = (body.image_ext ?? "jpg").toLowerCase();
        const imgPath = `receipts/${receiptId}.${ext}`;
        const storageResp = await fetch(
          `${supabaseUrl}/storage/v1/object/receipts/${imgPath}`,
          { method: "POST",
            headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}`, "Content-Type": `image/${ext}` },
            body: imgBuf }
        );
        if (storageResp.ok) {
          const publicUrl = `${supabaseUrl}/storage/v1/object/public/receipts/${imgPath}`;
          console.log(`[createFromChat] image uploaded OK, publicUrl=${publicUrl}`);
          // Include image_local_path directly in the existing receipt row via PATCH
          const patchResp = await fetch(`${supabaseUrl}/rest/v1/receipts?id=eq.${receiptId}`, {
            method: "PATCH",
            headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}`, "Content-Type": "application/json", Prefer: "return=representation" },
            body: JSON.stringify({ image_local_path: publicUrl }),
          });
          const patchBody = await patchResp.clone().text();
          console.log(`[createFromChat] PATCH status=${patchResp.status} body=${patchBody}`);
          if (!patchResp.ok) console.error("[createFromChat] PATCH failed:", patchBody);
        } else {
          const errText = await storageResp.text();
          console.error("Image upload failed:", errText);
        }
      }

      return new Response(JSON.stringify({ 
        success: true, 
        receipt_id: receiptId,
        needs_review: antiCheatReview,
        similar_receipts: similar_receipts,
      }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ── writeReceipt ─────────────────────────────────────────────────────
    if (action === "writeReceipt") {
      if (!body.receipt_id || !body.parse_result) {
        return new Response(JSON.stringify({ error: "receipt_id and parse_result required" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const pr = body.parse_result;
      const validPrdCodes: string[] = body.validPrdCodes ?? [];
      const validStoreCodes: string[] = body.validStoreCodes ?? [];
      const confidence = pr.parse_confidence ?? 0;
      
      // Get helper_id from the receipt
      let helperId = body.helper_id ?? null;
      if (!helperId) {
        const receiptMetaRes2 = await fetch(
          `${supabaseUrl}/rest/v1/receipts?id=eq.${body.receipt_id}&select=helper_id`,
          { headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` } }
        );
        const receiptMeta2 = await receiptMetaRes2.json();
        helperId = receiptMeta2?.[0]?.helper_id;
      }

      // Anti-cheat check
      const receiptItems = pr.items ?? [];
      const itemNames = receiptItems.map((i: any) => i.item_name ?? i.extracted_name ?? "").filter(Boolean);
      const { needs_review: antiCheatReview, similar_receipts } = await checkAntiCheat(
        supabaseUrl,
        supabaseKey,
        helperId ?? "",
        pr.transaction_date ?? "",
        validStoreCodes.includes(pr.store_cate) ? pr.store_cate : "other",
        pr.total_amount ?? 0,
        itemNames,
        body.receipt_id,
      );
      console.log(`[writeReceipt] anti-cheat: needs_review=${antiCheatReview}, similar=${similar_receipts.length}`);

      const needsReview = antiCheatReview || confidence < 0.7 || (pr.total_amount ?? 0) > 500;

      // Anomaly detection: if transaction_date differs from created_at by > 3 days, flag as suspicious
      // Note: caller should have passed created_at in body or we fetch it here
      let dateAnomaly = false;
      if (pr.transaction_date) {
        try {
          const receiptMetaRes = await fetch(
            `${supabaseUrl}/rest/v1/receipts?id=eq.${body.receipt_id}&select=created_at`,
            { headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` } }
          );
          if (receiptMetaRes.ok) {
            const rows = await receiptMetaRes.json();
            const createdAt = rows[0]?.created_at;
            if (createdAt) {
              const createdDate = new Date(createdAt);
              const txDate = new Date(pr.transaction_date);
              const diffMs = Math.abs(createdDate.getTime() - txDate.getTime());
              const diffDays = diffMs / (1000 * 60 * 60 * 24);
              dateAnomaly = diffDays > 3;
              console.log(`[writeReceipt] date_anomaly check: created=${createdDate.toISOString().split('T')[0]} tx=${pr.transaction_date} diff=${diffDays.toFixed(1)}d → anomaly=${dateAnomaly}`);
            }
          }
        } catch (e) {
          console.error("[writeReceipt] date_anomaly check failed:", e);
        }
      }

      const resp = await fetch(`${supabaseUrl}/rest/v1/receipts?id=eq.${body.receipt_id}`, {
        method: "PATCH",
        headers: {
          apikey: supabaseKey,
          Authorization: `Bearer ${supabaseKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          store_name: pr.store_name ?? "未知商戶",
          store_cate: validStoreCodes.includes(pr.store_cate) ? pr.store_cate : "other",
          location: pr.location ?? null,
          amount: pr.total_amount ?? null,
          transaction_date: pr.transaction_date ?? null,
          parsed_data: JSON.stringify(pr),
          parse_confidence: confidence,
          needs_review: needsReview,
          parse_status: "parsed",
          date_anomaly: dateAnomaly,
        }),
      });

      if (!resp.ok) {
        const err = await resp.text();
        errors.push(`receipt update failed (${resp.status}): ${err}`);
      }

      return new Response(JSON.stringify({
        success: resp.ok,
        errors: errors.length > 0 ? errors : undefined,
      }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ── writeItemsFromChat ─────────────────────────────────────────────────
    // Handles items from chat-parser (simpler format, no extracted_* fields)
    if (action === "writeItemsFromChat") {
      if (!body.receipt_id || !Array.isArray(body.items)) {
        return new Response(JSON.stringify({ error: "receipt_id and items[] required" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const validPrdCodes: string[] = body.validPrdCodes ?? [];
      const itemRows = body.items.map((item: any, idx: number) => {
        const selectedWeight = body.selected_weights?.[idx.toString()];
        return {
          receipt_id: body.receipt_id,
          item_name: item.item_name ?? item.item_raw_text ?? "",
          extracted_brand: null,
          extracted_name: item.item_name ?? item.item_raw_text ?? "",
          extracted_spec: null,
          item_raw_text: item.item_raw_text ?? item.item_name ?? "",
          qty: item.qty ?? 1,
          unit_price: item.unit_price ?? null,
          line_total: item.actual_price ?? (item.unit_price != null && item.qty != null ? item.unit_price * item.qty : null),
          prd_cate: validPrdCodes.includes(item.prd_cate) ? item.prd_cate : "other",
          subcategory_code: item.subcategory_code ?? null,
          weight_grams: selectedWeight ?? null,
        };
      });

      const resp = await fetch(`${supabaseUrl}/rest/v1/receipt_items`, {
        method: "POST",
        headers: {
          apikey: supabaseKey,
          Authorization: `Bearer ${supabaseKey}`,
          "Content-Type": "application/json",
          Prefer: "return=representation",
        },
        body: JSON.stringify(itemRows),
      });

      if (!resp.ok) {
        const err = await resp.text();
        errors.push(`receipt_items insert failed (${resp.status}): ${err}`);
      }


      const inserted = resp.ok ? await resp.json() : [];
      return new Response(JSON.stringify({
        success: resp.ok,
        count: inserted.length ?? 0,
        errors: errors.length > 0 ? errors : undefined,
      }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ── writeItems ────────────────────────────────────────────────────────
    if (action === "writeItems") {
      if (!body.receipt_id || !Array.isArray(body.items)) {
        return new Response(JSON.stringify({ error: "receipt_id and items[] required" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }


      const validPrdCodes: string[] = body.validPrdCodes ?? [];

      // Delete any existing items for this receipt first (idempotent — prevents duplicates on retry/re-run)
      await fetch(`${supabaseUrl}/rest/v1/receipt_items?receipt_id=eq.${body.receipt_id}`, {
        method: "DELETE",
        headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` },
      });

      const itemRows = body.items.map((item: any) => ({
        receipt_id: body.receipt_id,
        item_name: item.item_name ?? "",
        extracted_brand: item.extracted_brand ?? null,
        extracted_name: item.extracted_name ?? item.item_name ?? "",
        extracted_spec: item.extracted_spec ?? null,
        item_raw_text: item.item_raw_text ?? "",
        qty: item.qty ?? 1,
        unit_price: item.unit_price ?? null,
        line_total: item.unit_price != null && item.qty != null ? item.unit_price * item.qty : null,
        prd_cate: validPrdCodes.includes(item.prd_cate) ? item.prd_cate : "other",
      }));

      const resp = await fetch(`${supabaseUrl}/rest/v1/receipt_items`, {
        method: "POST",
        headers: {
          apikey: supabaseKey,
          Authorization: `Bearer ${supabaseKey}`,
          "Content-Type": "application/json",
          Prefer: "return=representation",
        },
        body: JSON.stringify(itemRows),
      });

      if (!resp.ok) {
        const err = await resp.text();
        errors.push(`receipt_items insert failed (${resp.status}): ${err}`);
      }

      const inserted = resp.ok ? await resp.json() : [];
      return new Response(JSON.stringify({
        success: resp.ok,
        count: inserted.length ?? 0,
        errors: errors.length > 0 ? errors : undefined,
      }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ── writePriceHistory ─────────────────────────────────────────────────
    if (action === "writePriceHistory") {
      if (!body.master_product_id || !body.item || !body.receipt_id) {
        return new Response(JSON.stringify({ error: "master_product_id, item and receipt_id required" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const { item, parse_result, receipt_id } = body;
      if (item.unit_price == null) {
        return new Response(JSON.stringify({ success: true, skipped: true, reason: "unit_price is null" }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const resp = await fetch(`${supabaseUrl}/rest/v1/price_history`, {
        method: "POST",
        headers: {
          apikey: supabaseKey,
          Authorization: `Bearer ${supabaseKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          master_product_id: body.master_product_id,
          region: parse_result?.location ?? null,
          location: parse_result?.location ?? null,
          price: item.unit_price,
          original_price: item.unit_price,
          unit: item.extracted_spec ?? "件",
          source_receipt_id: receipt_id,
          shop_id: body.shop_id ?? null,
          recorded_at: parse_result?.transaction_date ?? new Date().toISOString().split("T")[0],
        }),
      });

      if (!resp.ok) {
        const err = await resp.text();
        errors.push(`price_history insert failed (${resp.status}): ${err}`);
      }

      return new Response(JSON.stringify({
        success: resp.ok,
        errors: errors.length > 0 ? errors : undefined,
      }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ error: "Unknown action" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (error) {
    console.error("receipt-writer error:", error);
    return new Response(JSON.stringify({ success: false, error: error.message ?? "Internal error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});