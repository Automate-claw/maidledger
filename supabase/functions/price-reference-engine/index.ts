// ══════════════════════════════════════════════════════════════════════════════
// price-reference-engine — Three-layer Anchor Price Lookup
//
// Purpose: Returns the best available reference price ("Anchor") for a product.
// Layers (in priority order):
//   Layer 1: Consumer Council median price (cc_prices)
//   Layer 2: Own historical trimmed mean (45-day, freshness-weighted)
//   Layer 3: AFCD wholesale × retail_multiplier (future)
//
// Input:  { standard_name, master_product_id?, district?, store_type? }
// Output: { anchor_price, anchor_type, anchor_source, confidence }
// ══════════════════════════════════════════════════════════════════════════════
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// ─── Freshness weight (time decay) ──────────────────────────────────────────
function freshnessWeight(daysAgo: number): number {
  if (daysAgo === 0) return 1.0;
  if (daysAgo === 1) return 0.7;
  if (daysAgo === 2) return 0.3;
  if (daysAgo >= 3) return 0.1;
  return 0.05;
}

// ─── Layer 1: Consumer Council median ───────────────────────────────────────
async function getCcMedian(
  supabaseUrl: string,
  supabaseKey: string,
  standardName: string,
  brand?: string,
): Promise<{ price: number; source: string } | null> {
  // Search cc_prices by name_zh or name_en (fuzzy)
  const searchTerm = encodeURIComponent(standardName);
  const ccRes = await fetch(
    `${supabaseUrl}/rest/v1/cc_prices?or=(name_zh.ilike.*${searchTerm}*,name_en.ilike.*${searchTerm}*)&select=cc_code,name_zh,name_en,prices,price_per_100g&limit=5`,
    { headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` } }
  );
  const ccData = await ccRes.json();
  if (!Array.isArray(ccData) || ccData.length === 0) return null;

  // Parse prices JSON and compute median
  let allPrices: number[] = [];
  for (const row of ccData) {
    try {
      const prices: Record<string, number> = JSON.parse(row.prices ?? "{}");
      const vals = Object.values(prices).filter((v) => v > 0);
      allPrices = allPrices.concat(vals);
    } catch { /* skip malformed */ }
  }
  if (allPrices.length === 0) return null;

  allPrices.sort((a, b) => a - b);
  const median = allPrices.length % 2 === 0
    ? (allPrices[allPrices.length / 2 - 1] + allPrices[allPrices.length / 2]) / 2
    : allPrices[Math.floor(allPrices.length / 2)];

  // Use price_per_100g if available (already normalized)
  if (ccData[0].price_per_100g) {
    return { price: parseFloat(String(ccData[0].price_per_100g)), source: `cc:${ccData[0].cc_code}` };
  }
  return { price: median, source: `cc:${ccData[0].cc_code}` };
}

// ─── Layer 2: Own historical trimmed mean ───────────────────────────────────
async function getHistoricalTrimmedMean(
  supabaseUrl: string,
  supabaseKey: string,
  masterProductId: string,
  userId: string,
): Promise<{ price: number; source: string } | null> {
  const fortyFiveDaysAgo = new Date(Date.now() - 45 * 24 * 60 * 60 * 1000).toISOString().split("T")[0];
  const now = new Date().toISOString().split("T")[0];

  // Fetch 45-day history for this product + user, prefer normalized_unit_price
  const histRes = await fetch(
    `${supabaseUrl}/rest/v1/price_history?master_product_id=eq.${masterProductId}&user_id=eq.${userId}&recorded_at=gte.${fortyFiveDaysAgo}&recorded_at=lte.${now}&select=price,price_per_kg,price_per_pcs,recorded_at&order=recorded_at.desc&limit=100`,
    { headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` } }
  );
  const hist = await histRes.json();
  if (!Array.isArray(hist) || hist.length === 0) return null;

  // Build normalized price list (prefer price_per_kg, fallback to price)
  const prices: number[] = [];
  for (const row of hist) {
    const p = row.price_per_kg ?? row.price_per_pcs ?? parseFloat(String(row.price));
    if (p && p > 0) {
      const daysAgo = Math.floor(
        (new Date(now).getTime() - new Date(row.recorded_at).getTime()) / (1000 * 60 * 60 * 24)
      );
      // Weighted by freshness (only include recent enough data)
      if (freshnessWeight(daysAgo) >= 0.1) {
        prices.push(p);
      }
    }
  }
  if (prices.length < 2) {
    // Not enough data for trimmed mean, use simple average
    const avg = prices.length > 0 ? prices.reduce((a, b) => a + b, 0) / prices.length : 0;
    return avg > 0 ? { price: Math.round(avg * 100) / 100, source: "own_history_avg" } : null;
  }

  // Trimmed mean: remove top and bottom 10% (at least 1 each)
  prices.sort((a, b) => a - b);
  const trimCount = Math.max(1, Math.floor(prices.length * 0.1));
  const trimmed = prices.slice(trimCount, prices.length - trimCount);
  const mean = trimmed.reduce((a, b) => a + b, 0) / trimmed.length;
  return { price: Math.round(mean * 100) / 100, source: "own_history_trimmed_mean" };
}

// ─── Layer 3: AFCD wholesale × multiplier (stub for future) ────────────────
async function getAfcdAnchor(
  supabaseUrl: string,
  supabaseKey: string,
  standardName: string,
): Promise<{ price: number; source: string } | null> {
  const search = encodeURIComponent(standardName);
  const afRes = await fetch(
    `${supabaseUrl}/rest/v1/afcd_wholesale_prices?or=(item_name.ilike.*${search}*)&select=wholesale_price,unit,retail_multiplier&limit=1&order=recorded_date.desc`,
    { headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` } }
  );
  const afData = await afRes.json();
  if (!Array.isArray(afData) || afData.length === 0) return null;

  const row = afData[0];
  const multiplier = parseFloat(String(row.retail_multiplier)) || 2.0;
  const wholesale = parseFloat(String(row.wholesale_price));
  if (!wholesale) return null;

  // Convert to per-standard-unit (assume liang if unit contains 両, else kg)
  let perKg: number;
  if (row.unit && row.unit.includes("両")) {
    perKg = (wholesale * multiplier) / 0.60479; // 1 斤 ≈ 0.605 kg
  } else {
    perKg = wholesale * multiplier;
  }
  return { price: Math.round(perKg * 100) / 100, source: "afcd_wholesale" };
}

// ─── Main serve ─────────────────────────────────────────────────────────────
serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "";

    let body: any;
    try { body = await req.json(); } catch { body = {}; }

    const {
      standard_name,
      master_product_id,
      user_id,
      district,
      store_type,
    } = body;

    if (!standard_name && !master_product_id) {
      return new Response(JSON.stringify({ error: "standard_name or master_product_id required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const result = {
      anchor_price: null as number | null,
      anchor_type: null as string | null,
      anchor_source: null as string | null,
      confidence: 0,
    };

    // ── Try Layer 1: Consumer Council ────────────────────────────────────
    if (standard_name) {
      const cc = await getCcMedian(supabaseUrl, supabaseKey, standard_name);
      if (cc) {
        result.anchor_price = cc.price;
        result.anchor_type = "consumer_council";
        result.anchor_source = cc.source;
        result.confidence = 0.85;
        return new Response(JSON.stringify({ success: true, ...result }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    }

    // ── Try Layer 2: Own historical trimmed mean ─────────────────────────
    if (master_product_id && user_id) {
      const hist = await getHistoricalTrimmedMean(supabaseUrl, supabaseKey, master_product_id, user_id);
      if (hist) {
        result.anchor_price = hist.price;
        result.anchor_type = "own_history";
        result.anchor_source = hist.source;
        result.confidence = 0.7;
        return new Response(JSON.stringify({ success: true, ...result }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    }

    // ── Try Layer 3: AFCD wholesale ──────────────────────────────────────
    if (standard_name) {
      const af = await getAfcdAnchor(supabaseUrl, supabaseKey, standard_name);
      if (af) {
        result.anchor_price = af.price;
        result.anchor_type = "afcd_wholesale";
        result.anchor_source = af.source;
        result.confidence = 0.5;
        return new Response(JSON.stringify({ success: true, ...result }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    }

    // No anchor found
    return new Response(JSON.stringify({ success: true, ...result }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (error) {
    console.error("price-reference-engine error:", error);
    return new Response(JSON.stringify({ success: false, error: String(error) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
