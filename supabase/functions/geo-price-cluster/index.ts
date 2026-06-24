// ══════════════════════════════════════════════════════════════════════════════
// geo-price-cluster — Geographic price clustering
//
// Finds all receipts within a given geo radius and returns aggregated prices.
// Used for "same market" comparison — the most precise geo tier.
//
// Radius: 1.5km (walkable market catchment area)
// Minimum data: 3 shops, 10 items
//
// This is the most granular layer in the three-tier geo comparison:
//   Tier 1 (most precise): Same market / same shop cluster (1.5km radius)
//   Tier 2: Same district
//   Tier 3: Cross-district with index correction
//
// Input:  { lat, lng, standard_name, radius_km? }
// Output: { aggregated: {...}, shops_in_radius, confidence }
// ══════════════════════════════════════════════════════════════════════════════
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const EARTH_RADIUS_KM = 6371;
const DEFAULT_RADIUS_KM = 1.5;
const MIN_SHOPS = 3;
const MIN_ITEMS = 10;

// ─── Haversine distance ──────────────────────────────────────────────────────
function haversineKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return EARTH_RADIUS_KM * c;
}

// ─── Main serve ─────────────────────────────────────────────────────────────
serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "";

    let body: any;
    try { body = await req.json(); } catch { body = {}; }

    const { lat, lng, standard_name, radius_km = DEFAULT_RADIUS_KM } = body;

    if (lat == null || lng == null || !standard_name) {
      return new Response(JSON.stringify({ error: "lat, lng, and standard_name required" }), {
        status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const latNum = parseFloat(String(lat));
    const lngNum = parseFloat(String(lng));
    const radius = parseFloat(String(radius_km));

    // ── Step 1: Get all shops with geo coordinates ───────────────────────────
    const shopsRes = await fetch(
      `${supabaseUrl}/rest/v1/shops?latitude=not.is.null&longitude=not.is.null&select=id,canonical_name,latitude,longitude,shop_type`,
      { headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` } }
    );
    const shops = await shopsRes.json();
    if (!Array.isArray(shops) || shops.length === 0) {
      return new Response(JSON.stringify({
        success: true, available: false,
        reason: "No shops with geo coordinates in database yet",
      }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // ── Step 2: Filter shops within radius ───────────────────────────────────
    const nearbyShops = shops.filter((shop: any) => {
      const dist = haversineKm(latNum, lngNum, parseFloat(String(shop.latitude)), parseFloat(String(shop.longitude)));
      return dist <= radius;
    });

    if (nearbyShops.length < MIN_SHOPS) {
      return new Response(JSON.stringify({
        success: true, available: false,
        reason: `Not enough shops in radius (need ${MIN_SHOPS}, found ${nearbyShops.length})`,
        shops_in_radius: nearbyShops.length,
      }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const nearbyShopIds = nearbyShops.map((s: any) => s.id);

    // ── Step 3: Get receipt items from nearby shops within 48h ───────────────
    const cutoff48h = new Date(Date.now() - 48 * 60 * 60 * 1000).toISOString();
    const shopFilter = nearbyShopIds.map((id: string) => `shop_id=eq.${id}`).join("|");

    const itemsRes = await fetch(
      `${supabaseUrl}/rest/v1/receipt_items?select=normalized_unit_price,receipt_id,confidence_score&standard_name=ilike.*${encodeURIComponent(standard_name)}*&normalized_unit_price=not.is.null&confidence_score=gte.0.5&receipts(shop_id=in.(${nearbyShopIds.join(",")}),created_at=gte.${cutoff48h})`,
      { headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` } }
    );
    const items = await itemsRes.json();

    if (!Array.isArray(items) || items.length < MIN_ITEMS) {
      return new Response(JSON.stringify({
        success: true, available: false,
        reason: `Not enough price data in radius (need ${MIN_ITEMS}, found ${items?.length ?? 0})`,
        shops_in_radius: nearbyShops.length,
      }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // ── Step 4: Aggregate ───────────────────────────────────────────────────
    const prices = items.map((i: any) => parseFloat(String(i.normalized_unit_price))).filter((p: number) => p > 0);
    prices.sort((a: number, b: number) => a - b);

    const count = prices.length;
    const uniqueShops = new Set(items.map((i: any) => i.receipt_id)); // rough proxy

    const aggregated = {
      median: Math.round(median(prices) * 100) / 100,
      avg: Math.round((prices.reduce((a: number, b: number) => a + b, 0) / count) * 100) / 100,
      min: prices[0],
      max: prices[prices.length - 1],
      count,
      shop_count: nearbyShops.length,
      percentile_25: Math.round(percentile(prices, 0.25) * 100) / 100,
      percentile_75: Math.round(percentile(prices, 0.75) * 100) / 100,
    };

    const confidence = count >= 30 ? 0.85 : count >= 15 ? 0.7 : 0.55;

    return new Response(JSON.stringify({
      success: true,
      available: true,
      standard_name,
      aggregated,
      shops_in_radius: nearbyShops.map((s: any) => ({
        id: s.id,
        name: s.canonical_name,
        shop_type: s.shop_type,
      })),
      radius_km: radius,
      source: "geo_cluster_48h",
      confidence,
      freshness_window: "48h",
    }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });

  } catch (error) {
    console.error("geo-price-cluster error:", error);
    return new Response(JSON.stringify({ success: false, error: String(error) }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

function median(arr: number[]): number { return percentile(arr, 0.5); }
function percentile(arr: number[], p: number): number {
  const idx = Math.floor(arr.length * p);
  return arr[Math.min(idx, arr.length - 1)];
}
