import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

async function checkWeatherSuppression(supabaseUrl: string, supabaseKey: string, productCategory: string): Promise<boolean> {
  const now = new Date().toISOString();

  const res = await fetch(
    `${supabaseUrl}/rest/v1/price_alert_suppression?start_time=lte.${encodeURIComponent(now)}&end_time=gte.${encodeURIComponent(now)}&select=*`,
    { headers: { "apikey": supabaseKey, "Authorization": `Bearer ${supabaseKey}` } }
  );

  const suppressions = await res.json();
  if (!Array.isArray(suppressions) || suppressions.length === 0) return false;

  const active = suppressions[0];
  if (active.suppressed_categories && active.suppressed_categories.includes(productCategory)) {
    return true;
  }
  return false;
}

async function getPriceBaseline(
  supabaseUrl: string,
  supabaseKey: string,
  masterProductId: string,
  userId: string
): Promise<{ baseline: number; comparisonType: string }> {
  const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString().split('T')[0];
  const now = new Date().toISOString().split('T')[0];

  const recentRes = await fetch(
    `${supabaseUrl}/rest/v1/price_history?master_product_id=eq.${masterProductId}&user_id=eq.${userId}&order=recorded_at.desc&limit=7&select=price,recorded_at`,
    { headers: { "apikey": supabaseKey, "Authorization": `Bearer ${supabaseKey}` } }
  );
  const recentHistory = await recentRes.json();

  if (!Array.isArray(recentHistory) || recentHistory.length === 0) {
    return { baseline: 0, comparisonType: 'cold_start' };
  }

  const daysSinceLast = Math.floor(
    (new Date(now).getTime() - new Date(recentHistory[0].recorded_at).getTime()) / (1000 * 60 * 60 * 24)
  );

  if (daysSinceLast <= 6) {
    return { baseline: recentHistory[0].price, comparisonType: 'last_purchase' };
  }

  const sevenDayAvg = recentHistory.slice(0, 7).reduce((sum, r) => sum + parseFloat(r.price), 0) / Math.min(recentHistory.length, 7);
  return { baseline: sevenDayAvg, comparisonType: 'rolling_average' };
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { receipt_id, user_id } = await req.json();

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "";

    if (!receipt_id || !user_id) {
      return new Response(JSON.stringify({ error: "receipt_id and user_id required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const receiptRes = await fetch(
      `${supabaseUrl}/rest/v1/receipts?id=eq.${receipt_id}&select=*,receipt_items(master_product_id, item_name, unit_price, qty, prd_cate)`,
      { headers: { "apikey": supabaseKey, "Authorization": `Bearer ${supabaseKey}` } }
    );
    const receipts = await receiptRes.json();
    if (!Array.isArray(receipts) || receipts.length === 0) {
      return new Response(JSON.stringify({ error: "Receipt not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const receipt = receipts[0];
    const receiptItems = receipt.receipt_items || [];
    const alertsCreated: string[] = [];

    for (const item of receiptItems) {
      if (!item.master_product_id || !item.unit_price) continue;

      const { baseline, comparisonType } = await getPriceBaseline(supabaseUrl, supabaseKey, item.master_product_id, user_id);

      if (baseline === 0) continue;

      const threshold = 0.15;
      if (parseFloat(item.unit_price) > baseline * (1 + threshold)) {
        const weatherSuppressed = await checkWeatherSuppression(supabaseUrl, supabaseKey, item.prd_cate);

        const alertRes = await fetch(
          `${supabaseUrl}/rest/v1/price_alerts`,
          {
            method: "POST",
            headers: {
              "apikey": supabaseKey,
              "Authorization": `Bearer ${supabaseKey}`,
              "Content-Type": "application/json",
              "Prefer": "return=minimal",
            },
            body: JSON.stringify({
              user_id,
              master_product_id: item.master_product_id,
              alert_type: 'price_spike',
              threshold_pct: threshold * 100,
              current_price: parseFloat(item.unit_price),
              price_before: baseline,
              comparison_type: comparisonType,
              weather_suppressed: weatherSuppressed,
              region: receipt.location,
            }),
          },
        );

        if (alertRes.ok) {
          alertsCreated.push(item.master_product_id);
        }
      }
    }

    return new Response(
      JSON.stringify({ alerts_created: alertsCreated.length, alert_details: alertsCreated }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    console.error("price-alert-engine error:", error);
    return new Response(JSON.stringify({ error: String(error) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});