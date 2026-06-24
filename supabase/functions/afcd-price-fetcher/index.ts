// ══════════════════════════════════════════════════════════════════════════════
// afcd-price-fetcher — Fetch daily wholesale prices from AFCD
//
// Source: Hong Kong Agriculture, Fisheries and Conservation Department
// Info: https://www.afcd.gov.hk
//
// Supported categories:
//   蔬菜 (Vegetables) — Cheung Sha Wan Vegetable Market
//   淡水魚 (Fresh Water Fish) — Cheung Sha Wan Fresh Water Fish Market
//   海水魚 (Marine Fish) — Cheung Sha Wan Marine Fish Market
//
// Schedule: Daily via cron at 06:00 HKT (before morning markets open)
// Also callable manually: POST /functions/v1/afcd-price-fetcher
//
// Output: Upserts records into afcd_wholesale_prices table
// ══════════════════════════════════════════════════════════════════════════════
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// ─── AFCD page URLs (known patterns) ────────────────────────────────────────
// These are approximate URLs; AFCD structure changes frequently
const AFCD_URLS = {
  vegetable: "https://www.afcd.gov.hk/english/agriculture/agr_freshproduce/vegetable/vegetable.html",
  fish: "https://www.afcd.gov.hk/english/agriculture/agr_freshproduce/fish/fish.html",
};

// Fallback: use a static seed of known common items with estimated prices
// These are used when AFCD website is unreachable or parsing fails
const KNOWN_SEED_PRICES: Array<{ category: string; item_name: string; wholesale_price: number; unit: string }> = [
  // Vegetables (per 斤)
  { category: "蔬菜", item_name: "菜心", wholesale_price: 6.5, unit: "斤" },
  { category: "蔬菜", item_name: "白菜", wholesale_price: 5.0, unit: "斤" },
  { category: "蔬菜", item_name: "西蘭花", wholesale_price: 8.0, unit: "斤" },
  { category: "蔬菜", item_name: "生菜", wholesale_price: 4.5, unit: "斤" },
  { category: "蔬菜", item_name: "芥蘭", wholesale_price: 7.0, unit: "斤" },
  { category: "蔬菜", item_name: "茄子", wholesale_price: 7.5, unit: "斤" },
  { category: "蔬菜", item_name: "番茄", wholesale_price: 9.0, unit: "斤" },
  { category: "蔬菜", item_name: "土豆", wholesale_price: 5.5, unit: "斤" },
  // Fresh water fish (per 斤)
  { category: "淡水魚", item_name: "草魚", wholesale_price: 18.0, unit: "斤" },
  { category: "淡水魚", item_name: "大魚", wholesale_price: 15.0, unit: "斤" },
  { category: "淡水魚", item_name: "黃鱔", wholesale_price: 35.0, unit: "斤" },
  { category: "淡水魚", item_name: "鱔魚", wholesale_price: 30.0, unit: "斤" },
  // Marine fish (per 斤)
  { category: "海水魚", item_name: "紅衫魚", wholesale_price: 25.0, unit: "斤" },
  { category: "海水魚", item_name: "石斑", wholesale_price: 40.0, unit: "斤" },
  { category: "海水魚", item_name: "黃腳鱲", wholesale_price: 45.0, unit: "斤" },
];

// ─── Fetch + parse AFCD page ─────────────────────────────────────────────────
async function fetchAfcdPage(url: string): Promise<string | null> {
  try {
    const resp = await fetch(url, {
      headers: { "User-Agent": "Mozilla/5.0 (compatible; MaidLedger/1.0)" },
    });
    if (!resp.ok) return null;
    return await resp.text();
  } catch {
    return null;
  }
}

// ─── Parse AFCD HTML (simplified pattern matching) ───────────────────────────
// AFCD pages use table structures; this tries to extract price rows
// Format: <tr>...<td>item_name</td><td>price</td>...</tr>
function parseAfcdTable(html: string, category: string): Array<{ item_name: string; wholesale_price: number; unit: string }> {
  const results: Array<{ item_name: string; wholesale_price: number; unit: string }> = [];
  // Pattern: Chinese item name followed by a price (digits with optional decimal)
  const rowPattern = /<tr[^>]*>[\s\S]*?<td[^>]*>([\u4e00-\u9fffA-Za-z0-9\s]+)<\/td>[\s\S]*?<td[^>]*>[$]?([\d.]+)<\/td>/g;
  let match;
  while ((match = rowPattern.exec(html)) !== null) {
    const name = match[1].trim();
    const price = parseFloat(match[2]);
    if (name && price > 0 && name.length >= 2) {
      results.push({ category, item_name: name, wholesale_price: price, unit: "斤" });
    }
  }
  return results;
}

// ─── Upsert into afcd_wholesale_prices ───────────────────────────────────────
async function upsertRecords(
  supabaseUrl: string,
  supabaseKey: string,
  records: Array<{ category: string; item_name: string; wholesale_price: number; unit: string; recorded_date: string }>
) {
  if (records.length === 0) return 0;
  const body = records.map((r) => ({
    category: r.category,
    item_name: r.item_name,
    wholesale_price: r.wholesale_price,
    unit: r.unit,
    retail_multiplier: 2.0,
    recorded_date: r.recorded_date,
    created_at: new Date().toISOString(),
  }));

  const resp = await fetch(`${supabaseUrl}/rest/v1/afcd_wholesale_prices?upsert=true&on_conflict=category,item_name,recorded_date`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "apikey": supabaseKey,
      "Authorization": `Bearer ${supabaseKey}`,
      "Prefer": "resolution=merge-duplicates",
    },
    body: JSON.stringify(body),
  });
  if (!resp.ok) {
    const err = await resp.text();
    console.error("[afcd-price-fetcher] upsert failed:", err);
    return 0;
  }
  return records.length;
}

// ─── Main ───────────────────────────────────────────────────────────────────
serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "";

  if (!supabaseUrl || !supabaseKey) {
    return new Response(JSON.stringify({ error: "Missing Supabase config" }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const today = new Date().toISOString().split("T")[0];
  let totalUpserted = 0;
  let fetchErrors: string[] = [];
  const fetchResults: Record<string, number> = {};

  // ── Try fetching from AFCD website ─────────────────────────────────────────
  for (const [cat, url] of Object.entries(AFCD_URLS)) {
    const html = await fetchAfcdPage(url);
    if (!html) {
      fetchErrors.push(`${cat}: unreachable`);
      continue;
    }
    const records = parseAfcdTable(html, cat);
    if (records.length > 0) {
      const withDate = records.map((r) => ({ ...r, recorded_date: today }));
      const count = await upsertRecords(supabaseUrl, supabaseKey, withDate);
      totalUpserted += count;
      fetchResults[cat] = count;
    } else {
      fetchErrors.push(`${cat}: no records parsed (website structure may have changed)`);
    }
  }

  // ── If AFCD fetch failed or returned nothing, use seed prices ─────────────
  // This ensures the system always has baseline data for Layer 3 anchor
  if (totalUpserted === 0) {
    console.log("[afcd-price-fetcher] AFCD fetch unsuccessful, using seed prices");
    const withDate = KNOWN_SEED_PRICES.map((r) => ({ ...r, recorded_date: today }));
    const count = await upsertRecords(supabaseUrl, supabaseKey, withDate);
    totalUpserted += count;
    fetchResults["seed_fallback"] = count;
    fetchErrors.push("AFCD website unreachable — used seed prices as fallback");
  }

  return new Response(JSON.stringify({
    success: true,
    recorded_date: today,
    total_upserted: totalUpserted,
    by_category: fetchResults,
    errors: fetchErrors.length > 0 ? fetchErrors : undefined,
    note: "Seed fallback prices are conservative estimates. Verify against AFCD when website is reachable.",
  }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
