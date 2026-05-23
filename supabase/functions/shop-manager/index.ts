// ══════════════════════════════════════════════════════════════════════════════
// shop-manager — shop matching, creation and alias management
// Actions:
//   match      : { action:"match", raw_shop_name }
//   create     : { action:"create", raw_shop_name, shop_type?, location? }
//   upsert     : { action:"upsert", raw_shop_name, shop_type?, location? }
//   upsertAlias: { action:"upsertAlias", shop_id, raw_name }
//   get        : { action:"get", shop_id }
// ══════════════════════════════════════════════════════════════════════════════
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function escapeIlike(str: string) {
  return str.replace(/[%_\\]/g, "\\$&");
}

async function matchShop(supabaseUrl: string, supabaseKey: string, rawShopName: string): Promise<string | null> {
  // 1. Try exact alias match
  const aliasResp = await fetch(
    `${supabaseUrl}/rest/v1/shop_aliases?select=shop_id&raw_name.ilike.${encodeURIComponent(rawShopName)}&limit=1`,
    { headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` } }
  );
  const aliasShops = await aliasResp.json();
  if (aliasShops?.length > 0) return aliasShops[0].shop_id;

  // 2. Try canonical name match
  const nameResp = await fetch(
    `${supabaseUrl}/rest/v1/shops?select=id&canonical_name.ilike.${escapeIlike(rawShopName)}&limit=1`,
    { headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` } }
  );
  const nameShops = await nameResp.json();
  if (nameShops?.length > 0) return nameShops[0].id;

  return null;
}

async function createShop(supabaseUrl: string, supabaseKey: string, rawShopName: string, shopType?: string, location?: string): Promise<string> {
  const shopTypeMap: Record<string, string> = {
    supermarket: "supermarket",
    wet_market: "wet_market",
    convenience: "convenience",
    online: "online",
    restaurant: "restaurant",
    other: "other",
  };
  const mappedType = shopType && shopTypeMap[shopType] ? shopTypeMap[shopType] : "other";

  const shopResp = await fetch(`${supabaseUrl}/rest/v1/shops`, {
    method: "POST",
    headers: {
      apikey: supabaseKey,
      Authorization: `Bearer ${supabaseKey}`,
      "Content-Type": "application/json",
      Prefer: "return=representation",
    },
    body: JSON.stringify({
      canonical_name: rawShopName.trim(),
      shop_type: mappedType,
      region: location ?? null,
    }),
  });

  if (!shopResp.ok) {
    const err = await shopResp.text();
    throw new Error(`createShop failed (${shopResp.status}): ${err}`);
  }

  const shopJson = await shopResp.json();
  const shopId = shopJson[0]?.id ?? shopJson?.id;
  if (!shopId) throw new Error("createShop: no shop_id returned");

  // Also create alias entry
  await fetch(`${supabaseUrl}/rest/v1/shop_aliases`, {
    method: "POST",
    headers: {
      apikey: supabaseKey,
      Authorization: `Bearer ${supabaseKey}`,
      "Content-Type": "application/json",
      Prefer: "resolution=ignore-duplicates",
    },
    body: JSON.stringify({
      raw_name: rawShopName.trim(),
      shop_id: shopId,
      source: "ocr",
    }),
  });

  return shopId;
}

async function upsertShopAlias(supabaseUrl: string, supabaseKey: string, shopId: string, rawName: string): Promise<boolean> {
  try {
    const resp = await fetch(`${supabaseUrl}/rest/v1/shop_aliases`, {
      method: "POST",
      headers: {
        apikey: supabaseKey,
        Authorization: `Bearer ${supabaseKey}`,
        "Content-Type": "application/json",
        Prefer: "resolution=ignore-duplicates",
      },
      body: JSON.stringify({
        raw_name: rawName.trim(),
        shop_id: shopId,
        source: "ocr",
      }),
    });
    if (resp.status !== 201 && resp.status !== 200 && resp.status !== 409) {
      const err = await resp.text().catch(() => "(non-text response)");
      console.error(`upsertShopAlias warning (${resp.status}): ${err}`);
    }
    return true;
  } catch (e) {
    console.error(`upsertShopAlias exception:`, e);
    return false;
  }
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
      if (!body.shop_id) return new Response(JSON.stringify({ error: "shop_id required" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      const resp = await fetch(`${supabaseUrl}/rest/v1/shops?id=eq.${body.shop_id}`, {
        headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` },
      });
      const shops = await resp.json();
      return new Response(JSON.stringify({ success: true, data: shops[0] ?? null }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ── match ─────────────────────────────────────────────────────────────
    if (action === "match") {
      if (!body.raw_shop_name) return new Response(JSON.stringify({ error: "raw_shop_name required" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      const shopId = await matchShop(supabaseUrl, supabaseKey, body.raw_shop_name);
      return new Response(JSON.stringify({ success: true, shop_id: shopId, matched: !!shopId }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ── upsert ─────────────────────────────────────────────────────────────
    if (action === "upsert") {
      if (!body.raw_shop_name) return new Response(JSON.stringify({ error: "raw_shop_name required" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });

      let shopId: string | null = null;
      try {
        shopId = await matchShop(supabaseUrl, supabaseKey, body.raw_shop_name);
      } catch (e) {
        errors.push(`matchShop error: ${e}`);
      }

      if (!shopId) {
        try {
          shopId = await createShop(supabaseUrl, supabaseKey, body.raw_shop_name, body.shop_type, body.location);
        } catch (e) {
          errors.push(`createShop error: ${e}`);
        }
      } else {
        // Alias only for existing shop
        try {
          await upsertShopAlias(supabaseUrl, supabaseKey, shopId, body.raw_shop_name);
        } catch (e) {
          errors.push(`upsertShopAlias error: ${e}`);
        }
      }

      return new Response(JSON.stringify({
        success: !!shopId,
        shop_id: shopId,
        errors: errors.length > 0 ? errors : undefined,
      }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ── create ─────────────────────────────────────────────────────────────
    if (action === "create") {
      if (!body.raw_shop_name) return new Response(JSON.stringify({ error: "raw_shop_name required" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      try {
        const shopId = await createShop(supabaseUrl, supabaseKey, body.raw_shop_name, body.shop_type, body.location);
        return new Response(JSON.stringify({ success: true, shop_id: shopId }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      } catch (e) {
        return new Response(JSON.stringify({ success: false, error: String(e) }), {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    }

    // ── upsertAlias ─────────────────────────────────────────────────────────
    if (action === "upsertAlias") {
      if (!body.shop_id || !body.raw_name) {
        return new Response(JSON.stringify({ error: "shop_id and raw_name required" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      try {
        await upsertShopAlias(supabaseUrl, supabaseKey, body.shop_id, body.raw_name);
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

    return new Response(JSON.stringify({ error: "Unknown action" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (error) {
    console.error("shop-manager error:", error);
    return new Response(JSON.stringify({ success: false, error: error.message ?? "Internal error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});