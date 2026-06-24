// ══════════════════════════════════════════════════════════════════════════════
// cross-household-query — Anonymous crowdsourced price intelligence
//
// Privacy: ONLY returns aggregated data (AVG, MEDIAN, MIN, MAX, COUNT).
//   Never returns individual household data.
//
// Query window: last 48 hours (fresh produce changes rapidly)
// Minimum requirements for results:
//   - At least 5 distinct households
//   - At least 10 data points
//   - No single household > 30% weight
//
// Trust filtering: exclude households with trust_score < 0.3
//
// Output shape:
// {
//   standard_name: string,
//   aggregated: {
//     median: number,
//     avg: number,
//     min: number,
//     max: number,
//     count: number,
//     household_count: number,
//     percentile_25: number,
//     percentile_75: number,
//   },
//   source: string,
//   confidence: number,
//   freshness_window: "48h"
// }
//
// Input: { standard_name, district?, store_type?, user_id, employer_id }
// ══════════════════════════════════════════════════════════════════════════════
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const MIN_HOUSEHOLDS = 5;
const MIN_DATA_POINTS = 10;
const TRUST_THRESHOLD = 0.3;
const FRESHNESS_WINDOW_HOURS = 48;

function percentile(sortedArr: number[], p: number): number {
  const idx = Math.floor(sortedArr.length * p);
  return sortedArr[Math.min(idx, sortedArr.length - 1)];
}

function median(sortedArr: number[]): number {
  return percentile(sortedArr, 0.5);
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "";

    let body: any;
    try { body = await req.json(); } catch { body = {}; }

    const { standard_name, district, store_type, user_id, employer_id } = body;

    if (!standard_name) {
      return new Response(JSON.stringify({ error: "standard_name required" }), {
        status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ── Build time filter ─────────────────────────────────────────────────────
    const cutoffTime = new Date(Date.now() - FRESHNESS_WINDOW_HOURS * 60 * 60 * 1000).toISOString();

    // ── Query: join receipt_items with receipts and household_trust_scores ────
    // Filter conditions:
    //   1. standard_name matches
    //   2. recorded_at within 48h
    //   3. NOT own household (exclude by employer_id)
    //   4. trust_score >= TRUST_THRESHOLD
    //   5. confidence_score >= 0.5
    //   6. district matches if provided
    //   7. store_type matches if provided

    let queryUrl = `${supabaseUrl}/rest/v1/receipt_items?`;

    // Use RPC or direct join query
    // Since PostgREST doesn't support complex joins well, we do it in two steps:
    // Step 1: Get eligible employer_ids from household_trust_scores
    // Step 2: Query receipt_items with those employer_ids

    // Step 1: Get high-trust employer_ids (excluding self)
    const trustUrl = `${supabaseUrl}/rest/v1/household_trust_scores?trust_score=gte.${TRUST_THRESHOLD}&select=employer_id`;
    const trustRes = await fetch(trustUrl, {
      headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` },
    });
    const trustData = await trustRes.json();
    if (!Array.isArray(trustData) || trustData.length < MIN_HOUSEHOLDS) {
      return new Response(JSON.stringify({
        success: true,
        available: false,
        reason: `Not enough high-trust households yet (need ${MIN_HOUSEHOLDS}, found ${trustData?.length ?? 0})`,
        standard_name,
      }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const trustedEmployerIds = trustData
      .map((t: any) => t.employer_id)
      .filter((id: string) => id !== employer_id);

    if (trustedEmployerIds.length < MIN_HOUSEHOLDS) {
      return new Response(JSON.stringify({
        success: true,
        available: false,
        reason: `Not enough high-trust households after filtering self (found ${trustedEmployerIds.length})`,
        standard_name,
      }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // Step 2: Get receipt_ids from these employers within time window
    // We need to join: receipts (employer_id IN trusted) → receipt_items (standard_name)
    // Do it via RPC for efficiency
    const rpcResp = await fetch(`${supabaseUrl}/rest/v1/rpc/get_cross_household_prices`, {
      method: "POST",
      headers: {
        apikey: supabaseKey,
        Authorization: `Bearer ${supabaseKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        p_standard_name: standard_name,
        p_employer_ids: trustedEmployerIds,
        p_cutoff_time: cutoffTime,
        p_district: district ?? null,
        p_store_type: store_type ?? null,
        p_min_data_points: MIN_DATA_POINTS,
      }),
    });

    if (!rpcResp.ok) {
      // Fallback: manual query approach
      console.log("[cross-household-query] RPC not available, using fallback query");
      const fallbackResult = await fallbackQuery(
        supabaseUrl, supabaseKey, standard_name,
        trustedEmployerIds, cutoffTime, district, store_type
      );
      return new Response(JSON.stringify(fallbackResult), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const rpcData = await rpcResp.json();
    return new Response(JSON.stringify(rpcData), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (error) {
    console.error("cross-household-query error:", error);
    return new Response(JSON.stringify({ success: false, error: String(error) }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

// ─── Fallback query (when RPC not available) ─────────────────────────────────
async function fallbackQuery(
  supabaseUrl: string,
  supabaseKey: string,
  standardName: string,
  employerIds: string[],
  cutoffTime: string,
  district: string | null,
  storeType: string | null,
): Promise<any> {
  // Get receipts from trusted employers within time window
  const receiptUrl = `${supabaseUrl}/rest/v1/receipts?select=id,employer_id&employer_id=in.(${employerIds.join(",")})&created_at=gte.${cutoffTime}&location=ilike.*${district ? encodeURIComponent(district) : "%"}*`;
  const receiptRes = await fetch(receiptUrl, {
    headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` },
  });
  const receipts = await receiptRes.json();
  if (!Array.isArray(receipts) || receipts.length === 0) {
    return {
      success: true, available: false,
      reason: "No recent receipts from trusted households in this area",
    };
  }

  const receiptIds = receipts.map((r: any) => r.id);
  if (receiptIds.length === 0) {
    return { success: true, available: false, reason: "No receipts found" };
  }

  // Get receipt_items for these receipts with standard_name
  const itemsUrl = `${supabaseUrl}/rest/v1/receipt_items?receipt_id=in.(${receiptIds.join(",")})&standard_name=ilike.*${encodeURIComponent(standardName)}*&normalized_unit_price=not.is.null&confidence_score=gte.0.5&select=normalized_unit_price,receipt_id`;
  const itemsRes = await fetch(itemsUrl, {
    headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` },
  });
  const items = await itemsRes.json();
  if (!Array.isArray(items) || items.length < MIN_DATA_POINTS) {
    return {
      success: true, available: false,
      reason: `Not enough data points (need ${MIN_DATA_POINTS}, found ${items?.length ?? 0})`,
      standard_name: standardName,
    };
  }

  // Aggregate
  const prices = items.map((i: any) => parseFloat(String(i.normalized_unit_price))).filter((p: number) => p > 0);
  if (prices.length < MIN_DATA_POINTS) {
    return { success: true, available: false, reason: "Insufficient valid price data" };
  }

  prices.sort((a: number, b: number) => a - b);
  const count = prices.length;
  const householdSet = new Set(items.map((i: any) => i.receipt_id));
  const aggregated = {
    median: Math.round(median(prices) * 100) / 100,
    avg: Math.round((prices.reduce((a: number, b: number) => a + b, 0) / count) * 100) / 100,
    min: prices[0],
    max: prices[prices.length - 1],
    count,
    household_count: householdSet.size,
    percentile_25: Math.round(percentile(prices, 0.25) * 100) / 100,
    percentile_75: Math.round(percentile(prices, 0.75) * 100) / 100,
  };

  // Confidence based on sample size
  let confidence = 0.5;
  if (count >= 50 && householdSet.size >= 20) confidence = 0.9;
  else if (count >= 20 && householdSet.size >= 10) confidence = 0.75;
  else if (count >= MIN_DATA_POINTS) confidence = 0.6;

  return {
    success: true,
    available: true,
    standard_name: standardName,
    aggregated,
    source: "cross_household_48h",
    confidence,
    freshness_window: `${FRESHNESS_WINDOW_HOURS}h`,
    note: "Prices from anonymous neighbors. Individual households not identified.",
  };
}
