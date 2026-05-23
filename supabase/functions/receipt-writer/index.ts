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
          needs_review: false,
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

      return new Response(JSON.stringify({ success: true, receipt_id: receiptId }), {
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
      const needsReview = confidence < 0.7 || (pr.total_amount ?? 0) > 500;

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
      const itemRows = body.items.map((item: any) => ({
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

    // ── writeItems ────────────────────────────────────────────────────────
    if (action === "writeItems") {
      if (!body.receipt_id || !Array.isArray(body.items)) {
        return new Response(JSON.stringify({ error: "receipt_id and items[] required" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const validPrdCodes: string[] = body.validPrdCodes ?? [];
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