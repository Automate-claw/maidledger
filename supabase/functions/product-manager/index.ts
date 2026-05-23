// ══════════════════════════════════════════════════════════════════════════════
// product-manager — master product matching, creation and alias management
// Actions:
//   match         : { action:"match", item_name, prd_cate? }
//   create        : { action:"create", name, prd_cate? }
//   upsert        : { action:"upsert", item_name, prd_cate? }  → returns master_product_id
//   upsertAlias   : { action:"upsertAlias", master_product_id, raw_name }
//   get           : { action:"get", master_product_id }
// ══════════════════════════════════════════════════════════════════════════════
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function escapeIlike(str: string) {
  return str.replace(/[%_\\]/g, "\\$&");
}

async function upsertProductAlias(supabaseUrl: string, supabaseKey: string, rawName: string, masterProductId: string): Promise<boolean> {
  try {
    const resp = await fetch(`${supabaseUrl}/rest/v1/product_aliases`, {
      method: "POST",
      headers: {
        apikey: supabaseKey,
        Authorization: `Bearer ${supabaseKey}`,
        "Content-Type": "application/json",
        Prefer: "resolution=ignore-duplicates",
      },
      body: JSON.stringify({
        raw_name: rawName.trim(),
        master_product_id: masterProductId,
        source: "ocr",
      }),
    });
    // 201=created, 200=ok, 409=already exists — all fine
    if (resp.status !== 201 && resp.status !== 200 && resp.status !== 409) {
      const err = await resp.text().catch(() => "(non-text response)");
      console.error(`upsertProductAlias warning (${resp.status}): ${err}`);
    }
    return true;
  } catch (e) {
    // Non-fatal: don't let alias write failure break product creation
    console.error(`upsertProductAlias exception:`, e);
    return false;
  }
}

async function matchProduct(supabaseUrl: string, supabaseKey: string, itemName: string, prdCate?: string): Promise<string | null> {
  // 1. Try exact alias match
  const aliasResp = await fetch(
    `${supabaseUrl}/rest/v1/product_aliases?select=master_product_id&raw_name=eq.${encodeURIComponent(itemName)}&limit=1`,
    { headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` } }
  );
  const aliases = await aliasResp.json();
  if (aliases?.length > 0) return aliases[0].master_product_id;

  // 2. Keyword search on canonical_name
  const keywords = itemName.trim().split(/[\s　]+/).filter((k) => k.length > 1).slice(0, 3);
  if (keywords.length === 0) return null;

  const orParts = keywords.map((kw) => `canonical_name.ilike.%${escapeIlike(kw)}%`).join(",");
  const catFilter = prdCate && prdCate !== "other" ? `&prd_cate=eq.${prdCate}` : "";

  const mpResp = await fetch(
    `${supabaseUrl}/rest/v1/master_products?select=id&or=(${orParts})${catFilter}&limit=5`,
    { headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` } }
  );
  const products = await mpResp.json();
  if (products?.length > 0) {
    await upsertProductAlias(supabaseUrl, supabaseKey, itemName, products[0].id);
    return products[0].id;
  }

  return null;
}

async function createMasterProduct(supabaseUrl: string, supabaseKey: string, name: string, prdCate: string): Promise<string> {
  const mpResp = await fetch(`${supabaseUrl}/rest/v1/master_products`, {
    method: "POST",
    headers: {
      apikey: supabaseKey,
      Authorization: `Bearer ${supabaseKey}`,
      "Content-Type": "application/json",
      Prefer: "return=representation",
    },
    body: JSON.stringify({
      canonical_name: name.trim(),
      prd_cate: prdCate || "other",
      default_unit: "件",
    }),
  });

  if (!mpResp.ok) {
    const err = await mpResp.text();
    throw new Error(`createMasterProduct failed (${mpResp.status}): ${err}`);
  }

  const mp = await mpResp.json();
  const mpId = mp[0]?.id ?? mp?.id;
  if (!mpId) throw new Error("createMasterProduct: no id returned");

  await upsertProductAlias(supabaseUrl, supabaseKey, name, mpId);
  return mpId;
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

    // ── get ────────────────────────────────────────────────────────────────
    if (action === "get") {
      if (!body.master_product_id) {
        return new Response(JSON.stringify({ error: "master_product_id required" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      const resp = await fetch(`${supabaseUrl}/rest/v1/master_products?id=eq.${body.master_product_id}`, {
        headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` },
      });
      const products = await resp.json();
      return new Response(JSON.stringify({ success: true, data: products[0] ?? null }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ── upsertAlias ─────────────────────────────────────────────────────────
    if (action === "upsertAlias") {
      if (!body.master_product_id || !body.raw_name) {
        return new Response(JSON.stringify({ error: "master_product_id and raw_name required" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      try {
        await upsertProductAlias(supabaseUrl, supabaseKey, body.raw_name, body.master_product_id);
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

    // ── create ─────────────────────────────────────────────────────────────
    if (action === "create") {
      if (!body.name) {
        return new Response(JSON.stringify({ error: "name required" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      try {
        const mpId = await createMasterProduct(supabaseUrl, supabaseKey, body.name, body.prd_cate || "other");
        return new Response(JSON.stringify({ success: true, master_product_id: mpId }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      } catch (e) {
        return new Response(JSON.stringify({ success: false, error: String(e) }), {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    }

    // ── match ─────────────────────────────────────────────────────────────
    if (action === "match") {
      if (!body.item_name) {
        return new Response(JSON.stringify({ error: "item_name required" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      try {
        const mpId = await matchProduct(supabaseUrl, supabaseKey, body.item_name, body.prd_cate);
        return new Response(JSON.stringify({ success: true, master_product_id: mpId, matched: !!mpId }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      } catch (e) {
        return new Response(JSON.stringify({ success: false, error: String(e) }), {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    }

    // ── upsert (match OR create) ──────────────────────────────────────────
    if (action === "upsert") {
      if (!body.item_name) {
        return new Response(JSON.stringify({ error: "item_name required" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      let masterProductId: string | null = null;

      // Try match first
      try {
        masterProductId = await matchProduct(supabaseUrl, supabaseKey, body.item_name, body.prd_cate);
      } catch (e) {
        errors.push(`matchProduct error: ${e}`);
      }

      // If not found, create
      if (!masterProductId) {
        try {
          masterProductId = await createMasterProduct(supabaseUrl, supabaseKey, body.item_name, body.prd_cate || "other");
        } catch (e) {
          errors.push(`createMasterProduct error: ${e}`);
        }
      }

      return new Response(JSON.stringify({
        success: !!masterProductId,
        master_product_id: masterProductId,
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
    console.error("product-manager error:", error);
    return new Response(JSON.stringify({ success: false, error: error.message ?? "Internal error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});