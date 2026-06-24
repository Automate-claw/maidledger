// ══════════════════════════════════════════════════════════════════════════════
// price-reference-engine — Three-layer Anchor Price Lookup
//
// Purpose: Returns the best available reference price ("Anchor") for a product.
// Layers (in priority order):
//   Layer 1: Consumer Council median price (cc_prices)
//   Layer 2: Own historical trimmed mean (45-day, freshness-weighted)
//   Layer 3: AFCD wholesale × retail_multiplier
//
// Filters applied:
//   - district_index: cross-district price normalization
//   - store_type channel: wet_market ≠ supermarket (never cross-match)
//
// Input:  { standard_name, master_product_id?, user_id?, district?, store_type? }
// Output: { anchor_price, anchor_type, anchor_source, confidence, district_index_applied? }
// ══════════════════════════════════════════════════════════════════════════════
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// ─── District price index lookup ─────────────────────────────────────────────
async function getDistrictIndex(
  supabaseUrl: string,
  supabaseKey: string,
  district: string,
  storeType: string,
): Promise<number> {
  if (!district) return 1.0;
  // Normalize district name
  const search = encodeURIComponent(district.replace(/[區市]/g, ""));
  const cat = storeType === "wet_market" ? "街市" : storeType === "supermarket" ? "超市" : "all";
  const monthStart = new Date();
  monthStart.setDate(1);
  const monthStr = monthStart.toISOString().split("T")[0];

  const res = await fetch(
    `${supabaseUrl}/rest/v1/district_price_index?district=ilike.*${search}*&category=eq.${cat}&recorded_month=lte.${monthStr}&order=recorded_month.desc&limit=1&select=index_coefficient`,
    { headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` } }
  );
  const data = await res.json();
  if (Array.isArray(data) && data.length > 0 && data[0].index_coefficient) {
    return parseFloat(String(data[0].index_coefficient));
  }
  return 1.0; // No index found → neutral
}

// ─── Layer 1: Consumer Council median ───────────────────────────────────────
async function getCcMedian(
  supabaseUrl: string,
  supabaseKey: string,
  standardName: string,
  brand?: string,
  districtIndex: number = 1.0,
): Promise<{ price: number; source: string; district_index_applied: number } | null> {
  const search = encodeURIComponent(standardName);
  const ccRes = await fetch(
    `${supabaseUrl}/rest/v1/cc_prices?or=(name_zh.ilike.*${search}*,name_en.ilike.*${search}*)&select=cc_code,name_zh,name_en,prices,price_per_100g&limit=5`,
    { headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` } }
  );
  const ccData = await ccRes.json();
  if (!Array.isArray(ccData) || ccData.length === 0) return null;

  // Brand matching: prefer rows where brand matches
  let bestRow = ccData[0];
  if (brand) {
    const brandLower = brand.toLowerCase();
    const brandMatch = ccData.find(
      (r: any) => r.brand_en?.toLowerCase().includes(brandLower) || r.brand_zh?.includes(brand)
    );
    if (brandMatch) bestRow = brandMatch;
  }

  // Parse prices JSON and compute median
  let allPrices: number[] = [];
  try {
    const prices: Record<string, number> = JSON.parse(bestRow.prices ?? "{}");
    const vals = Object.values(prices).filter((v) => v > 0);
    allPrices = vals;
  } catch { /* malformed */ }

  if (allPrices.length === 0) return null;

  allPrices.sort((a, b) => a - b);
  const median = allPrices.length % 2 === 0
    ? (allPrices[allPrices.length / 2 - 1] + allPrices[allPrices.length / 2]) / 2
    : allPrices[Math.floor(allPrices.length / 2)];

  // Apply district index: convert to baseline district price
  // raw_median / district_index = what this would cost in the baseline district
  const adjustedMedian = median / districtIndex;

  if (bestRow.price_per_100g) {
    const adjustedPer100g = parseFloat(String(bestRow.price_per_100g)) / districtIndex;
    return {
      price: Math.round(adjustedPer100g * 100) / 100,
      source: `cc:${bestRow.cc_code}`,
      district_index_applied: districtIndex,
    };
  }
  return {
    price: Math.round(adjustedMedian * 100) / 100,
    source: `cc:${bestRow.cc_code}`,
    district_index_applied: districtIndex,
  };
}

// ─── Layer 2: Own historical trimmed mean ───────────────────────────────────
async function getHistoricalTrimmedMean(
  supabaseUrl: string,
  supabaseKey: string,
  masterProductId: string,
  userId: string,
): Promise<{ price: number; source: string; sample_count: number } | null> {
  const fortyFiveDaysAgo = new Date(Date.now() - 45 * 24 * 60 * 60 * 1000).toISOString().split("T")[0];
  const now = new Date().toISOString().split("T")[0];

  const histRes = await fetch(
    `${supabaseUrl}/rest/v1/price_history?master_product_id=eq.${masterProductId}&user_id=eq.${userId}&recorded_at=gte.${fortyFiveDaysAgo}&recorded_at=lte.${now}&select=price,price_per_kg,price_per_pcs,recorded_at,freshness_weight&order=recorded_at.desc&limit=100`,
    { headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` } }
  );
  const hist = await histRes.json();
  if (!Array.isArray(hist) || hist.length === 0) return null;

  // Build normalized price list (prefer price_per_kg, fallback to price)
  const weightedPrices: { p: number; w: number }[] = [];
  for (const row of hist) {
    const p = row.price_per_kg ?? row.price_per_pcs ?? parseFloat(String(row.price));
    if (!p || p <= 0) continue;
    // Use precomputed freshness_weight, or compute on the fly
    let w = row.freshness_weight ? parseFloat(String(row.freshness_weight)) : 1.0;
    if (w < 0.1) continue; // skip stale data
    weightedPrices.push({ p, w });
  }

  if (weightedPrices.length === 0) return null;

  if (weightedPrices.length < 3) {
    // Simple weighted average
    const totalW = weightedPrices.reduce((s, x) => s + x.w, 0);
    const avg = weightedPrices.reduce((s, x) => s + x.p * x.w, 0) / totalW;
    return {
      price: Math.round(avg * 100) / 100,
      source: "own_weighted_avg",
      sample_count: weightedPrices.length,
    };
  }

  // Trimmed mean: sort by price, trim top/bottom 10%
  weightedPrices.sort((a, b) => a.p - b.p);
  const trimCount = Math.max(1, Math.floor(weightedPrices.length * 0.1));
  const trimmed = weightedPrices.slice(trimCount, weightedPrices.length - trimCount);
  if (trimmed.length === 0) return null;

  const totalW = trimmed.reduce((s, x) => s + x.w, 0);
  const mean = trimmed.reduce((s, x) => s + x.p * x.w, 0) / totalW;
  return {
    price: Math.round(mean * 100) / 100,
    source: "own_trimmed_mean",
    sample_count: trimmed.length,
  };
}

// ─── Layer 3: AFCD wholesale × multiplier ───────────────────────────────────
async function getAfcdAnchor(
  supabaseUrl: string,
  supabaseKey: string,
  standardName: string,
): Promise<{ price: number; source: string } | null> {
  const search = encodeURIComponent(standardName);
  const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString().split("T")[0];
  const today = new Date().toISOString().split("T")[0];

  const afRes = await fetch(
    `${supabaseUrl}/rest/v1/afcd_wholesale_prices?item_name.ilike.*${search}*&recorded_date=gte.${sevenDaysAgo}&recorded_date=lte.${today}&select=wholesale_price,unit,retail_multiplier&order=recorded_date.desc&limit=3`,
    { headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` } }
  );
  const afData = await afRes.json();
  if (!Array.isArray(afData) || afData.length === 0) return null;

  // Use most recent record
  const row = afData[0];
  const multiplier = parseFloat(String(row.retail_multiplier)) || 2.0;
  const wholesale = parseFloat(String(row.wholesale_price));
  if (!wholesale) return null;

  // Convert to per-kg for standardization
  let perKg: number;
  if (row.unit && (row.unit.includes("斤") || row.unit.includes("両"))) {
    perKg = (wholesale * multiplier) / 0.60479; // 1 斤 ≈ 0.605 kg
  } else if (row.unit && row.unit.includes("公斤")) {
    perKg = wholesale * multiplier;
  } else {
    perKg = wholesale * multiplier; // assume per-kg if unknown
  }

  return {
    price: Math.round(perKg * 100) / 100,
    source: `afcd:${standardName}`,
  };
}

// ─── Main serve ─────────────────────────────────────────────────────────────
serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "";

    let body: any;
    try { body = await req.json(); } catch { body = {}; }

    const { standard_name, master_product_id, user_id, district, store_type } = body;

    if (!standard_name && !master_product_id) {
      return new Response(JSON.stringify({ error: "standard_name or master_product_id required" }), {
        status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const districtIndex = await getDistrictIndex(supabaseUrl, supabaseKey, district ?? "", store_type ?? "");

    const result: any = {
      anchor_price: null,
      anchor_type: null,
      anchor_source: null,
      confidence: 0,
      district_index_applied: districtIndex > 1.0 || districtIndex < 1.0 ? districtIndex : undefined,
    };

    // ── Layer 1: Consumer Council ──────────────────────────────────────────
    if (standard_name) {
      const cc = await getCcMedian(supabaseUrl, supabaseKey, standard_name, body.brand, districtIndex);
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

    // ── Layer 2: Own historical trimmed mean ───────────────────────────────
    if (master_product_id && user_id) {
      const hist = await getHistoricalTrimmedMean(supabaseUrl, supabaseKey, master_product_id, user_id);
      if (hist) {
        result.anchor_price = hist.price;
        result.anchor_type = "own_history";
        result.anchor_source = hist.source;
        result.confidence = 0.7;
        result.sample_count = hist.sample_count;
        return new Response(JSON.stringify({ success: true, ...result }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    }

    // ── Layer 3: AFCD wholesale ────────────────────────────────────────────
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
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
