// ══════════════════════════════════════════════════════════════════════════════
// price-alert-engine — Layered Buffer Zone + Channel Filtering + Three-Layer Anchor
//
// Stage 1 upgrade from fixed 15% threshold:
//   D = (A - B) / B × 100%
//
// Packed goods buffer (store_type = supermarket / discount):
//   D < -15%   → 🟢 買得好平
//   -15% ≤ D ≤ +12%  → ⚪ 合理市價（靜音）
//   +12% < D ≤ +35%  → 🟡 略高（輕提示）
//   D > +35%   → 🔴 買貴咗
//   D > +150%  → ⚠️ 數據異常（OCR 疑似出錯）
//
// Fresh food buffer (wet_market, is_fresh_food = true):
//   D < -20%   → 🟢 買得好平
//   -20% ≤ D ≤ +20%  → ⚪ 合理市價（靜音）
//   +20% < D ≤ +40%  → 🟡 略高
//   D > +40%   → 🔴 買貴咗
//   D > +150%  → ⚠️ 數據異常
//
// Channel铁律: wet_market 只跟 wet_market 数据比, supermarket 只跟 supermarket 比
// ══════════════════════════════════════════════════════════════════════════════
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// ─── Freshness decay ────────────────────────────────────────────────────────
function freshnessWeight(daysAgo: number): number {
  if (daysAgo === 0) return 1.0;
  if (daysAgo === 1) return 0.7;
  if (daysAgo === 2) return 0.3;
  if (daysAgo >= 3) return 0.1;
  return 0.05;
}

// ─── Trimmed mean from price history ────────────────────────────────────────
async function getTrimmedMeanAnchor(
  supabaseUrl: string,
  supabaseKey: string,
  masterProductId: string,
  userId: string,
): Promise<{ anchor: number; source: string } | null> {
  const fortyFiveDaysAgo = new Date(Date.now() - 45 * 24 * 60 * 60 * 1000).toISOString().split("T")[0];
  const now = new Date().toISOString().split("T")[0];

  const histRes = await fetch(
    `${supabaseUrl}/rest/v1/price_history?master_product_id=eq.${masterProductId}&user_id=eq.${userId}&recorded_at=gte.${fortyFiveDaysAgo}&recorded_at=lte.${now}&select=price,price_per_kg,price_per_pcs,recorded_at,shop_id&order=recorded_at.desc&limit=100`,
    { headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` }
  );
  const hist = await histRes.json();
  if (!Array.isArray(hist) || hist.length === 0) return null;

  // Prefer normalized price fields, weighted by freshness
  const weightedPrices: { p: number; w: number }[] = [];
  for (const row of hist) {
    const p = row.price_per_kg ?? row.price_per_pcs ?? parseFloat(String(row.price));
    if (!p || p <= 0) continue;
    const daysAgo = Math.floor(
      (new Date(now).getTime() - new Date(row.recorded_at).getTime()) / (1000 * 60 * 60 * 24)
    );
    const w = freshnessWeight(daysAgo);
    if (w >= 0.1) weightedPrices.push({ p, w });
  }
  if (weightedPrices.length === 0) return null;

  if (weightedPrices.length < 3) {
    // Not enough data for trimmed mean → simple weighted average
    const totalW = weightedPrices.reduce((s, x) => s + x.w, 0);
    const avg = weightedPrices.reduce((s, x) => s + x.p * x.w, 0) / totalW;
    return { anchor: Math.round(avg * 100) / 100, source: "own_weighted_avg" };
  }

  // Trimmed mean: sort by price, trim top/bottom 10%
  weightedPrices.sort((a, b) => a.p - b.p);
  const trimCount = Math.max(1, Math.floor(weightedPrices.length * 0.1));
  const trimmed = weightedPrices.slice(trimCount, weightedPrices.length - trimCount);
  if (trimmed.length === 0) return null;
  const mean = trimmed.reduce((s, x) => s + x.p * x.w, 0) / trimmed.reduce((s, x) => s + x.w, 0);
  return { anchor: Math.round(mean * 100) / 100, source: "own_trimmed_mean" };
}

// ─── Weather suppression ─────────────────────────────────────────────────────
async function checkWeatherSuppression(
  supabaseUrl: string,
  supabaseKey: string,
  productCategory: string
): Promise<boolean> {
  const now = new Date().toISOString();
  const res = await fetch(
    `${supabaseUrl}/rest/v1/price_alert_suppression?start_time=lte.${encodeURIComponent(now)}&end_time=gte.${encodeURIComponent(now)}&select=*`,
    { headers: { "apikey": supabaseKey, "Authorization": `Bearer ${supabaseKey}` } }
  );
  const suppressions = await res.json();
  if (!Array.isArray(suppressions) || suppressions.length === 0) return false;
  const active = suppressions[0];
  return !!(active.suppressed_categories && active.suppressed_categories.includes(productCategory));
}

// ─── Buffer zone classification ───────────────────────────────────────────────
type AlertLevel = "green" | "neutral" | "yellow" | "red" | "anomaly";

interface BufferResult {
  level: AlertLevel;
  level_label: string;
  alert_type: string;
  d_pct: number;
  threshold_lo: number;
  threshold_hi: number;
}

function classifyPriceDiff(dPct: number, isFreshFood: boolean, currentPrice: number): BufferResult {
  if (isFreshFood) {
    // Fresh food: wider buffer (±20%)
    if (dPct < -20)        return { level: "green",   level_label: "🟢 買得好平",  alert_type: "good_deal",     d_pct: dPct, threshold_lo: -Infinity, threshold_hi: -20 };
    if (dPct <= +20)      return { level: "neutral", level_label: "⚪ 合理市價",  alert_type: "reasonable",   d_pct: dPct, threshold_lo: -20,       threshold_hi: +20 };
    if (dPct <= +40)      return { level: "yellow",  level_label: "🟡 略高於市價", alert_type: "slightly_high", d_pct: dPct, threshold_lo: +20,       threshold_hi: +40 };
    if (dPct <= +150)     return { level: "red",     level_label: "🔴 買貴咗",     alert_type: "price_spike",  d_pct: dPct, threshold_lo: +40,       threshold_hi: +150 };
    return { level: "anomaly", level_label: "⚠️ 數據異常", alert_type: "data_anomaly", d_pct: dPct, threshold_lo: +150, threshold_hi: Infinity };
  } else {
    // Packed goods: tighter buffer (±12%)
    if (dPct < -15)        return { level: "green",   level_label: "🟢 買得好平",   alert_type: "good_deal",     d_pct: d_pct, threshold_lo: -Infinity, threshold_hi: -15 };
    if (dPct <= +12)      return { level: "neutral", level_label: "⚪ 合理市價",   alert_type: "reasonable",   d_pct: d_pct, threshold_lo: -15,       threshold_hi: +12 };
    if (dPct <= +35)      return { level: "yellow",  level_label: "🟡 略高於市價", alert_type: "slightly_high", d_pct: d_pct, threshold_lo: +12,       threshold_hi: +35 };
    if (dPct <= +150)     return { level: "red",     level_label: "🔴 買貴咗",     alert_type: "price_spike",  d_pct: d_pct, threshold_lo: +35,       threshold_hi: +150 };
    return { level: "anomaly", level_label: "⚠️ 數據異常", alert_type: "data_anomaly", d_pct: d_pct, threshold_lo: +150, threshold_hi: Infinity };
  }
}

// ─── Humanized message builder ───────────────────────────────────────────────
function buildAlertMessage(
  itemName: string,
  currentPrice: number,
  anchorPrice: number,
  dPct: number,
  level: AlertLevel,
  isFreshFood: boolean,
  location: string | null,
): string {
  const emoji = level === "green" ? "🟢" : level === "yellow" ? "🟡" : level === "red" ? "🔴" : "⚠️";
  const direction = dPct > 0 ? "高" : "低";
  const absPct = Math.abs(dPct).toFixed(1);

  if (level === "anomaly") {
    return `${emoji} **數據異常警告：${itemName}**

本次單價：**$${currentPrice}**
參考均價：$${anchorPrice}
偏離幅度：+${absPct}%

系統懷疑 OCR 識別可能有誤（如將 $12 誤讀為 $120，或將 100g 當成 1kg）。建議核對實物單據。`;
  }

  if (level === "green") {
    return `${emoji} **買得好平！${itemName}**

本次單價：**$${currentPrice}**
參考均價：$${anchorPrice}
比市價低 ${absPct}%

精明消費，姐姐幫你慳錢了！`;
  }

  if (level === "neutral") return ""; // Silent zone

  // Yellow or Red: humanized message
  const weatherHint = isFreshFood && location
    ? `街市生鮮受品質、早市/收市或天氣影響較大，`
    : `超市價格亦受促銷、进货渠道影響，`;

  return `${emoji} **價格異動提示：${itemName}**

本次單價：**$${currentPrice}**
參考均價：$${anchorPrice}
偏離幅度：${dPct > 0 ? "+" : ""}${dPct.toFixed(1)}%

*💡 系統小建議：${weatherHint}建議留意實物品質是否物有所值，再判斷是否需要調整採買習慣。*`;
}

// ─── Main serve ───────────────────────────────────────────────────────────────
serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const { receipt_id, user_id } = await req.json();
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "";

    if (!receipt_id || !user_id) {
      return new Response(JSON.stringify({ error: "receipt_id and user_id required" }), {
        status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Fetch receipt with items (now including new normalized fields)
    const receiptRes = await fetch(
      `${supabaseUrl}/rest/v1/receipts?id=eq.${receipt_id}&select=*,receipt_items(master_product_id,item_name,unit_price,normalized_unit_price,prd_cate,is_fresh_food,confidence_score,standard_name,shop_id)`,
      { headers: { "apikey": supabaseKey, "Authorization": `Bearer ${supabaseKey}` } }
    );
    const receipts = await receiptRes.json();
    if (!Array.isArray(receipts) || receipts.length === 0) {
      return new Response(JSON.stringify({ error: "Receipt not found" }), {
        status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const receipt = receipts[0];
    const receiptItems = receipt.receipt_items || [];
    const alerts: any[] = [];

    for (const item of receiptItems) {
      // Skip if no master_product_id or low confidence
      if (!item.master_product_id) continue;
      if (item.confidence_score != null && item.confidence_score < 0.5) {
        console.log(`[price-alert] skipping ${item.item_name}: confidence=${item.confidence_score} < 0.5`);
        continue;
      }

      // Use normalized_unit_price if available (Stage 1 core change)
      const currentPrice = item.normalized_unit_price ?? item.unit_price;
      if (currentPrice == null || currentPrice <= 0) continue;

      // Get anchor from own historical trimmed mean (Layer 2)
      const anchor = await getTrimmedMeanAnchor(supabaseUrl, supabaseKey, item.master_product_id, user_id);
      if (!anchor) {
        console.log(`[price-alert] no anchor for ${item.item_name} (master_product_id=${item.master_product_id})`);
        continue;
      }

      // Calculate D = (A - B) / B × 100%
      const dPct = ((currentPrice - anchor.anchor) / anchor.anchor) * 100;

      const isFreshFood = item.is_fresh_food ?? false;
      const classification = classifyPriceDiff(dPct, isFreshFood, currentPrice);

      // Neutral zone → no alert
      if (classification.level === "neutral") continue;

      // Check weather suppression
      const weatherSuppressed = await checkWeatherSuppression(supabaseUrl, supabaseKey, item.prd_cate);
      if (weatherSuppressed && classification.level !== "anomaly") {
        console.log(`[price-alert] weather suppressed: ${item.item_name} (prd_cate=${item.prd_cate})`);
        continue;
      }

      // Build humanized message
      const message = buildAlertMessage(
        item.standard_name ?? item.item_name,
        currentPrice,
        anchor.anchor,
        dPct,
        classification.level,
        isFreshFood,
        receipt.location,
      );

      // Write alert
      const alertRes = await fetch(`${supabaseUrl}/rest/v1/price_alerts`, {
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
          alert_type: classification.alert_type,
          threshold_pct: classification.threshold_hi,
          current_price: currentPrice,
          price_before: anchor.anchor,
          comparison_type: anchor.source,
          weather_suppressed: weatherSuppressed,
          region: receipt.location,
          d_pct: Math.round(dPct * 10) / 10,
          is_fresh_food: isFreshFood,
          message,
        }),
      });

      if (alertRes.ok) {
        alerts.push({ item_name: item.item_name, level: classification.level, d_pct: dPct, message });
      }
    }

    return new Response(JSON.stringify({
      alerts_created: alerts.length,
      alerts,
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (error) {
    console.error("price-alert-engine error:", error);
    return new Response(JSON.stringify({ error: String(error) }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
