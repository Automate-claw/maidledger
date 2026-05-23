// ══════════════════════════════════════════════════════════════════════════════
// receipt-writer — writes parsed receipt data to DB
// Handles: receipt update, receipt_items, price_history, shop link
//
// Actions:
//   writeReceipt     : { action:"writeReceipt", receipt_id, parse_result, validPrdCodes }
//   writeItems       : { action:"writeItems", receipt_id, items[], validPrdCodes }
//   writePriceHistory: { action:"writePriceHistory", master_product_id, item, parse_result, receipt_id }
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