// Receipt Vision Model Benchmark
// Tests gpt-4o vs gemini-2.5-flash vs qwen3-vl-30b on 3 receipt images
// Deploy and call via: POST /functions/v1/receipt-benchmark

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const MODELS: Record<string, { input: number; output: number }> = {
  "openai/gpt-4o": { input: 2.50, output: 10.0 },
  "google/gemini-2.5-flash": { input: 0.125, output: 0.50 },
  "qwen/qwen3-vl-30b-a3b-instruct": { input: 0.13, output: 0.40 },
};

const SYSTEM_PROMPT = `你係一個香港收據分析助手。請直接睇呢張收據圖片，提取結構化資料。
【重要】輸出必須係「純」JSON，唔好包含任何URL編碼、HTML實體、Markdown code blocks或其他特殊格式。
Output format:
{"store_name":"","store_cate":"","location":"","total_amount":0,"transaction_date":"YYYY-MM-DD","items":[{"item_name":"","extracted_brand":null,"extracted_name":"","extracted_spec":null,"item_raw_text":"","qty":1,"unit_price":null,"prd_cate":""}],"parse_confidence":0.0}`;

const TEST_IMAGES = [
  { name: "McDonald's", url: "https://hnyazfrkzpxdjiyfzemm.supabase.co/storage/v1/object/public/receipts/receipts/receipt_1779612357802.jpg" },
  { name: "太興", url: "https://hnyazfrkzpxdjiyfzemm.supabase.co/storage/v1/object/public/receipts/receipts/receipt_1779609910997.jpg" },
  { name: "759阿信屋", url: "https://hnyazfrkzpxdjiyfzemm.supabase.co/storage/v1/object/public/receipts/receipts/receipt_1779612585108.jpg" },
];

async function callVision(model: string, imageUrl: string): Promise<any> {
  const start = Date.now();
  const openRouterKey = Deno.env.get("OPENROUTER_API_KEY") ?? "";
  try {
    const resp = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${openRouterKey}`,
        "Content-Type": "application/json",
        "HTTP-Referer": "https://maidledger.app",
        "X-Title": "MaidLedger-Benchmark",
      },
      body: JSON.stringify({
        model,
        messages: [{ role: "user", content: [
          { type: "text", text: SYSTEM_PROMPT },
          { type: "image_url", image_url: { url: imageUrl } }
        ]}],
        temperature: 0.2,
        max_tokens: 2048,
      }),
    });
    const elapsed = Date.now() - start;
    const data = await resp.json();
    const usage = data?.usage ?? {};
    const text = data?.choices?.[0]?.message?.content ?? "";
    let items_count = 0;
    try {
      const stripped = text.replace(/```json\n?/, "").replace(/```\n?/, "").trim();
      const match = stripped.match(/\{[\s\S]*\}/);
      if (match) {
        const parsed = JSON.parse(match[0]);
        items_count = parsed.items?.length ?? 0;
      }
    } catch { items_count = -1; }
    const pricing = MODELS[model] || { input: 1, output: 1 };
    const cost = (pricing.input * (usage.prompt_tokens || 0) + pricing.output * (usage.completion_tokens || 0)) / 1e6;
    return { ok: resp.ok, status: resp.status, elapsed, items_count, usage, cost_usd: cost, text: text.substring(0, 80), error: data?.error?.message };
  } catch (e) {
    return { ok: false, elapsed: 0, items_count: 0, usage: {}, cost_usd: 0, text: "", error: String(e) };
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  if (req.method === "GET" && new URL(req.url).pathname.endsWith("health")) {
    return new Response(JSON.stringify({ status: "ok", timestamp: Date.now() }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    let body: any = {};
    try { body = await req.json(); } catch {}
    const results: any = {};

    for (const img of TEST_IMAGES) {
      results[img.name] = {};
      for (const model of Object.keys(MODELS)) {
        process.stdout.write(`${img.name}/${model}... `);
        const r = await callVision(model, img.url);
        results[img.name][model] = r;
        const usd = r.cost_usd.toFixed(6);
        console.log(`${r.ok ? "OK" : "FAIL"} | ${r.elapsed}ms | items:${r.items_count} | tokens:${r.usage.prompt_tokens}/${r.usage.completion_tokens}/${r.usage.total_tokens} | ~$${usd}`);
        if (r.error) console.log(`  Error: ${r.error}`);
        await new Promise(re => setTimeout(re, 500));
      }
    }

    return new Response(JSON.stringify({ results }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("Benchmark error:", e);
    return new Response(JSON.stringify({ error: e.message ?? String(e) }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
