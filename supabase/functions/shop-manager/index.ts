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

// Escape single quotes for PostgreSQL LIKE/ILIKE patterns (used in REST API URLs)
function escapeLike(str: string): string {
  return str.replace(/'/g, "''");
}

// Infer district/region from a location string using HK area knowledge
function inferDistrict(location?: string): { region: string | null; district: string | null } {
  if (!location) return { region: null, district: null };

  const text = location.trim();

  // Direct region mappings
  const regionMap: Record<string, string> = {
    "東區": "東區", "中西區": "中西區", "南區": "南區", "灣仔": "灣仔",
    "九龍城": "九龍城", "黃大仙": "黃大仙", "觀塘": "觀塘", "油尖旺": "油尖旺",
    "深水埗": "深水埗", "沙田": "沙田", "大埔": "大埔", "北區": "北區",
    "西貢": "西貢", "荃灣": "荃灣", "屯門": "屯門", "元朗": "元朗",
    "葵青": "葵青", "離島": "離島",
  };

  // District → Region mappings
  const districtToRegion: Record<string, string> = {
    // Eastern
    "筲箕灣": "東區", "柴灣": "東區", "北角": "東區", "西灣河": "東區",
    "愛蝶灣": "東區", "鯉景灣": "東區", "太古城": "東區",
    // Southern
    "薄扶林": "南區", "香港仔": "南區", "鴨脷洲": "南區", "赤柱": "南區",
    "淺水灣": "南區", "舂坎角": "南區",
    // Wan Chai
    "灣仔": "灣仔", "銅鑼灣": "灣仔", "跑馬地": "灣仔",
    // Central & Western
    "中環": "中西區", "上環": "中西區", "西環": "中西區", "堅尼地城": "中西區",
    // Kowloon City
    "九龍城": "九龍城", "何文田": "九龍城", "紅磡": "九龍城", "土瓜灣": "九龍城",
    "九龍塘": "九龍城",
    // Yau Tsim Mong
    "油麻地": "油尖旺", "旺角": "油尖旺", "尖沙咀": "油尖旺",
    // Sham Shui Po
    "深水埗": "深水埗", "長沙灣": "深水埗", "荔枝角": "深水埗",
    // Wong Tai Sin / Kwun Tong
    "黃大仙": "黃大仙", "慈雲山": "黃大仙", "彩虹": "黃大仙",
    "觀塘": "觀塘", "牛頭角": "觀塘", "九龍灣": "觀塘", "油塘": "觀塘",
    // New Territories
    "沙田": "沙田", "大圍": "沙田", "馬鞍山": "沙田", "火炭": "沙田",
    "大埔": "大埔", "上水": "北區", "粉嶺": "北區", "坪輋": "北區",
    "將軍澳": "西貢", "坑口": "西貢", "西貢市": "西貢",
    "荃灣": "荃灣", "梨木樹": "荃灣",
    "屯門": "屯門", "良景": "屯門", "建生": "屯門",
    "元朗": "元朗", "天水圍": "元朗", "屏山": "元朗", "洪水橋": "元朗",
    "葵涌": "葵青", "荔景": "葵青", "青衣": "葵青",
    "東涌": "離島", "大嶼山": "離島", "愉景灣": "離島",
  };

  // 1. Check direct region mentions
  for (const [key, region] of Object.entries(regionMap)) {
    if (text.includes(key)) return { region, district: key };
  }

  // 2. Check district keywords
  for (const [district, region] of Object.entries(districtToRegion)) {
    if (text.includes(district)) return { region, district };
  }

  return { region: null, district: null };
}

async function matchShop(supabaseUrl: string, supabaseKey: string, rawShopName: string): Promise<string | null> {
  const normalized = normalizeShopName(rawShopName);
  const lower = normalized.toLowerCase();

  // 1. Fetch all aliases and match in JS (bypasses ILIKE single-quote URL-encoding issues)
  const aliasResp = await fetch(
    `${supabaseUrl}/rest/v1/shop_aliases?select=shop_id,raw_name&limit=200`,
    { headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` } }
  );
  const aliases: Array<{ shop_id: string; raw_name: string }> = await aliasResp.json();
  // Exact match on normalized name
  const exactMatch = aliases.find((a) => normalizeShopName(a.raw_name).toLowerCase() === lower);
  if (exactMatch) return exactMatch.shop_id;

  // 2. Try canonical name match
  const nameResp = await fetch(
    `${supabaseUrl}/rest/v1/shops?select=id,canonical_name&limit=200`,
    { headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` } }
  );
  const shops: Array<{ id: string; canonical_name: string }> = await nameResp.json();
  const nameMatch = shops.find((s) => normalizeShopName(s.canonical_name).toLowerCase() === lower);
  if (nameMatch) return nameMatch.id;

  return null;
}

// Strip branch numbers like " (199)" from shop names for canonical matching
function normalizeShopName(name: string): string {
  return name
    .replace(/\s*\(\d+\)\s*$/, "")  // remove trailing " (199)"
    .replace(/\s*#\d+\s*$/, "")      // remove trailing " #199"
    .replace(/\s+/g, " ")
    .trim();
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

  // Infer district from location string using common HK area knowledge
  const { region, district } = inferDistrict(location);

  const shopResp = await fetch(`${supabaseUrl}/rest/v1/shops`, {
    method: "POST",
    headers: {
      apikey: supabaseKey,
      Authorization: `Bearer ${supabaseKey}`,
      "Content-Type": "application/json",
      Prefer: "return=representation",
    },
    body: JSON.stringify({
      canonical_name: normalizeShopName(rawShopName.trim()),
      shop_type: mappedType,
      region: region ?? null,
      district: district ?? null,
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