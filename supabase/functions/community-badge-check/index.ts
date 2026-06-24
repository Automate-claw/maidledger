// ══════════════════════════════════════════════════════════════════════════════
// community-badge-check — Weekly badge awarding logic
//
// Checks if a household qualifies for a 「精明眼」 weekly badge:
//   Criteria:
//     - Total weekly spend is >15% below district average
//     - At least 10 different items purchased (variety)
//     - No single-category heavy skew (>70% in one category)
//     - At least 5 distinct shopping trips in the week
//
// Badge: "本週【XX區街市精明眼】前 5%"
// Message format: "姐姐本週躋身【將軍澳區街市精明眼】前 5%，幫你慳咗約 $240！"
//
// Triggered: Daily via cron, or on-demand when employer opens dashboard
// ══════════════════════════════════════════════════════════════════════════════
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface BadgeCheckResult {
  eligible: boolean;
  badge_type?: string;
  district?: string;
  savings_vs_district?: number;
  percentile_rank?: number;
  total_spent?: number;
  district_avg_spent?: number;
  message?: string;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "";

    let body: any;
    try { body = await req.json(); } catch { body = {}; }

    const { employer_id, district } = body;
    if (!employer_id) {
      return new Response(JSON.stringify({ error: "employer_id required" }), {
        status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ── Compute this household's weekly stats ───────────────────────────────
    const weekStart = new Date();
    weekStart.setDate(weekStart.getDate() - 7);
    const weekStartStr = weekStart.toISOString().split("T")[0];
    const today = new Date().toISOString().split("T")[0];

    // Get all receipts for this employer in past 7 days
    const receiptRes = await fetch(
      `${supabaseUrl}/rest/v1/receipts?employer_id=eq.${employer_id}&transaction_date=gte.${weekStartStr}&transaction_date=lte.${today}&select=id,amount,location,store_cate`,
      { headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` } }
    );
    const receipts = await receiptRes.json();
    if (!Array.isArray(receipts) || receipts.length < 5) {
      return new Response(JSON.stringify({ eligible: false, reason: "Insufficient shopping trips this week (< 5)" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Get receipt items for variety analysis
    const receiptIds = receipts.map((r: any) => r.id);
    const itemsRes = await fetch(
      `${supabaseUrl}/rest/v1/receipt_items?receipt_id=in.(${receiptIds.join(",")})&select=prd_cate,normalized_unit_price`,
      { headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` } }
    );
    const items = await itemsRes.json();
    if (!Array.isArray(items)) {
      return new Response(JSON.stringify({ eligible: false, reason: "Could not fetch items" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const totalSpent = receipts.reduce((sum: number, r: any) => sum + parseFloat(String(r.amount ?? 0)), 0, 0);
    const itemCount = items.length;
    const uniqueCategories = new Set(items.map((i: any) => i.prd_cate)).size;

    // Check variety (at least 10 different items)
    if (itemCount < 10) {
      return new Response(JSON.stringify({ eligible: false, reason: `Low variety (${itemCount} items, need ≥10)` }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Check category skew (no single category > 70%)
    const categoryCounts: Record<string, number> = {};
    for (const i of items) {
      categoryCounts[i.prd_cate] = (categoryCounts[i.prd_cate] || 0) + 1;
    }
    const maxCategoryPct = Math.max(...Object.values(categoryCounts).map(c => c / itemCount));
    if (maxCategoryPct > 0.7) {
      return new Response(JSON.stringify({ eligible: false, reason: `Category skew too high (${(maxCategoryPct * 100).toFixed(0)}% in one category)` }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ── Get district average for comparison ──────────────────────────────────
    const districtParam = encodeURIComponent(district ?? receipts[0]?.location ?? "");
    if (!districtParam) {
      return new Response(JSON.stringify({ eligible: false, reason: "No district info available" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Get all employer_ids in same district (excluding self)
    const sameDistrictRes = await fetch(
      `${supabaseUrl}/rest/v1/receipts?location=ilike.*${districtParam}*&employer_id=not.eq.${employer_id}&transaction_date=gte.${weekStartStr}&transaction_date=lte.${today}&select=employer_id,amount`,
      { headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` } }
    );
    const sameDistrictReceipts = await sameDistrictRes.json();
    if (!Array.isArray(sameDistrictReceipts) || sameDistrictReceipts.length < 10) {
      return new Response(JSON.stringify({ eligible: false, reason: "Not enough district data for comparison" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Compute per-employer spend in district
    const employerSpends: Record<string, number> = {};
    for (const r of sameDistrictReceipts) {
      employerSpends[r.employer_id] = (employerSpends[r.employer_id] || 0) + parseFloat(String(r.amount));
    }
    const allSpends = Object.values(employerSpends);
    const districtAvg = allSpends.reduce((a: number, b: number) => a + b, 0) / allSpends.length;

    // Check savings threshold (>15% below district average)
    const savingsPct = (districtAvg - totalSpent) / districtAvg;
    if (savingsPct < 0.15) {
      return new Response(JSON.stringify({
        eligible: false,
        reason: `Savings ${(savingsPct * 100).toFixed(1)}% below 15% threshold`,
        total_spent: Math.round(totalSpent * 100) / 100,
        district_avg: Math.round(districtAvg * 100) / 100,
      }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // Compute percentile rank
    const belowCount = allSpends.filter((s: number) => s > totalSpent).length;
    const percentileRank = ((belowCount / allSpends.length) * 100);

    if (percentileRank < 95) {
      // Not top 5%, but still a good deal — could award at lower tiers later
      return new Response(JSON.stringify({ eligible: false, reason: `Ranked ${percentileRank.toFixed(1)}%, need top 5%` }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const savings = districtAvg - totalSpent;
    const districtName = district ?? districtParam;

    // Build encouraging message
    const message = `🎉 恭喜！姐姐本週躋身【${districtName}街市精明眼】前 5%，幫你慳咗約 $${Math.round(savings)}！`;

    const result: BadgeCheckResult = {
      eligible: true,
      badge_type: "smart_eye_weekly",
      district: districtName,
      savings_vs_district: Math.round(savings * 100) / 100,
      percentile_rank: Math.round(percentileRank * 100) / 100,
      total_spent: Math.round(totalSpent * 100) / 100,
      district_avg_spent: Math.round(districtAvg * 100) / 100,
      message,
    };

    // Award badge in DB
    await fetch(`${supabaseUrl}/rest/v1/community_badges`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "apikey": supabaseKey,
        "Authorization": `Bearer ${supabaseKey}`,
        Prefer: "resolution=ignore-duplicates",
      },
      body: JSON.stringify({
        employer_id,
        badge_type: "smart_eye_weekly",
        district: districtName,
        period_start: weekStartStr,
        period_end: today,
        savings_vs_district: result.savings_vs_district,
        percentile_rank: result.percentile_rank,
        total_spent: result.total_spent,
        district_avg_spent: result.district_avg_spent,
      }),
    });

    return new Response(JSON.stringify(result), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (error) {
    console.error("community-badge-check error:", error);
    return new Response(JSON.stringify({ success: false, error: String(error) }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
