// ══════════════════════════════════════════════════════════════════════════════
// receipt-vision — Pure LLM Vision receipt parser (no ML Kit OCR)
// Uses OpenRouter multimodal models to directly analyze receipt images
//
// Input:  { image_base64?, image_url?, store_cate_hint?, location_hint? }
// Output: { success, data: { store_name, store_cate, location, total_amount,
//           transaction_date, items[], parse_confidence }, tokens_used }
//
// Token cost estimation (for comparison with ML Kit approach):
//   1080p image ≈ 2000-2500 tokens (vision API overhead)
//   Output text ≈ 400-600 tokens
//   Total: ~2500-3000 tokens per receipt (vs ~1500 with ML Kit + LLM)
// ══════════════════════════════════════════════════════════════════════════════
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// ── Categories cache ────────────────────────────────────────────────────────
let categoriesCache: { storeCategories: any[]; prdCategories: any[]; fetchedAt: number } | null = null;
const CACHE_TTL_MS = 5 * 60 * 1000;

async function getCategories(supabaseUrl: string, supabaseKey: string) {
  if (categoriesCache && Date.now() - categoriesCache.fetchedAt < CACHE_TTL_MS) {
    return categoriesCache;
  }
  const [storeRes, prdRes] = await Promise.all([
    fetch(`${supabaseUrl}/rest/v1/store_categories?select=code,name_tc&order=display_order.asc`, {
      headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` },
    }),
    fetch(`${supabaseUrl}/rest/v1/prd_categories?select=code,name_tc&order=display_order.asc`, {
      headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` },
    }),
  ]);
  const storeCategories = await storeRes.json();
  const prdCategories = await prdRes.json();
  categoriesCache = { storeCategories, prdCategories, fetchedAt: Date.now() };
  return categoriesCache;
}

// ── JSON helper ────────────────────────────────────────────────────────────
function parseJsonResponse(text: string) {
  // Strip markdown code blocks if present
  const stripped = text.replace(/```json\n?/, "").replace(/```\n?/, "").trim();
  const jsonMatch = stripped.match(/\{[\s\S]*\}/);
  if (!jsonMatch) throw new Error(`No JSON found in LLM response. Raw response: ${stripped.substring(0, 500)}`);
  return JSON.parse(jsonMatch[0]);
}

// ── LLM Vision call ─────────────────────────────────────────────────────────
// Returns { textResponse, usage } where usage = { prompt_tokens, completion_tokens, total_tokens }
async function callLLMVision(
  imageData: string, // base64 data URL or URL
  supabaseUrl: string,
  supabaseKey: string,
): Promise<{ textResponse: string; usage: { prompt_tokens: number; completion_tokens: number; total_tokens: number } }> {
  const openRouterKey = Deno.env.get("OPENROUTER_API_KEY") ?? "";
  if (!openRouterKey) throw new Error("OPENROUTER_API_KEY not configured");

  const cats = await getCategories(supabaseUrl, supabaseKey);
  const STORE_CATEGORIES = cats.storeCategories;
  const PRD_CATEGORIES = cats.prdCategories;

  // Build image content for OpenRouter's OpenAI-compatible multimodal API
  // Format for OpenAI-compatible API: { type: "image_url", image_url: { url: "..." } }
  let imageContent: any;
  if (imageData.startsWith("data:")) {
    // Direct base64 data URL
    imageContent = { type: "image_url", image_url: { url: imageData } };
  } else if (imageData.startsWith("http")) {
    // Public URL
    imageContent = { type: "image_url", image_url: { url: imageData } };
  } else {
    // Raw base64 — wrap in data URL
    imageContent = { type: "image_url", image_url: { url: `data:image/jpeg;base64,${imageData}` } };
  }

  const prompt = `你係一個香港收據分析助手。請直接睇呢張收據圖片，提取結構化資料。

【重要】輸出必須係「純」JSON，唔好包含任何URL編碼、HTML實體、Markdown code blocks或其他特殊格式。所有文字必須係可以直接閱讀的繁體中文。

## 有效商店類別（請從以下選擇 store_cate）：
${STORE_CATEGORIES.map((c) => `- ${c.code} = ${c.name_tc}`).join("\n")}

## 有效產品類別（請從以下選擇 prd_cate）：
${PRD_CATEGORIES.map((c) => `- ${c.code} = ${c.name_tc}`).join("\n")}

## 香港地區名稱（用於 location）：
中環、上環、西環、堅尼地城、香港仔、薄扶林、山頂、灣仔、銅鑼灣、跑馬地、北角、鰂魚涌、筲箕灣、西灣河、柴灣、九龍城、九龍塘、旺角、太子、深水埗、長沙灣、荔枝角、美孚、黃大仙、彩虹、觀塘、牛頭角、九龍灣、油塘、藍田、鯉魚門、新蒲崗、沙田、大圍、火炭、馬鞍山、科學園、大埔、上水、粉嶺、元朗、天水圍、屯門、荃灣、葵涌、青衣、將軍澳、坑口、調景嶺、西貢、清水灣、其他

## 輸出格式（只輸出JSON）：
{
  "store_name": "店舖名稱（從圖片中識別）",
  "store_cate": "有效的store_cate code",
  "location": "地區名稱",
  "total_amount": 數字或null,
  "transaction_date": "YYYY-MM-DD格式或null",
  "items": [
    {
      "item_name": "產品的原始完整名稱",
      "extracted_brand": "品牌名稱，無則填 null",
      "extracted_name": "去除品牌、容量、店鋪特異字眼後的純產品核心名稱",
      "extracted_spec": "規格容量，無則填 null",
      "item_raw_text": "原始OCR行文字",
      "qty": 數量,
      "unit_price": 單價或null,
      "prd_cate": "有效的prd_cate code"
    }
  ],
  "parse_confidence": 0.0-1.0,
  "vision_notes": "任何視覺分析時注意到的問題（如模糊、手寫、部分遮擋等）"
}

### 分析規則
- 直接睇圖片，唔需要假設 OCR 文字格式
- item + price 靠視覺上的位置關係配對（通常左邊係項目名，右邊係價格）
- 識別所有可見的產品，唔只係總額附近嘅項目
- 如果有「小計/合計/TOTAL」區域，請特別標註
- 金額唔需要加$符號，直接填數字
- parse_confidence 反映對整體解析結果的信心程度`;

  const model = "qwen/qwen3-vl-30b-a3b-instruct"; // Primary vision model (switch to gpt-4o if quality degrades)

  let lastError = "";
  let textResponse = "";
  let usage = { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 };

  try {
    const resp = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${openRouterKey}`,
        "Content-Type": "application/json",
        "HTTP-Referer": "https://maidledger.app",
        "X-Title": "MaidLedger Receipt Vision",
      },
      body: JSON.stringify({
        model,
        messages: [
          {
            role: "user",
            content: [
              { type: "text", text: prompt },
              imageContent, // already in OpenAI vision format: { type: "image_url", image_url: { url: "..." } }
            ],
          },
        ],
        temperature: 0.2,
        max_tokens: 2048,
      }),
    });

    if (!resp.ok) {
      lastError = await resp.text();
      throw new Error(`OpenRouter error ${resp.status}: ${lastError}`);
    }

    const data = await resp.json();
    console.error("[receipt-vision] LLM raw response:", JSON.stringify(data));
    textResponse = data?.choices?.[0]?.message?.content ?? "";

    if (data?.usage) {
      usage = {
        prompt_tokens: data.usage.prompt_tokens ?? 0,
        completion_tokens: data.usage.completion_tokens ?? 0,
        total_tokens: data.usage.total_tokens ?? 0,
      };
    }
  } catch (e) {
    lastError = String(e);
    throw new Error(`Vision model failed: ${lastError}`);
  }

  if (!textResponse) throw new Error(`Empty response from vision model. Raw data was logged.`);
  return { textResponse, usage };
}

// ─────────────────────────────────────────────────────────────────────────────
serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  // Debug: log incoming headers
  console.log("[receipt-vision] incoming headers:", JSON.stringify(Object.fromEntries(req.headers.entries())));

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    console.log("[receipt-vision] supabaseUrl present:", !!supabaseUrl, "supabaseKey present:", !!supabaseKey);

    let body: any;
    try { body = await req.json(); } catch { body = {}; }

    const imageBase64 = body.image_base64;
    const imageUrl = body.image_url;
    const storeCateHint = body.store_cate_hint;
    const locationHint = body.location_hint;

    if (!imageBase64 && !imageUrl) {
      return new Response(JSON.stringify({ error: "image_base64 or image_url is required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const imageData = imageBase64 || imageUrl;

    const { textResponse, usage } = await callLLMVision(imageData, supabaseUrl, supabaseKey);
    const parseResult = parseJsonResponse(textResponse);

    return new Response(JSON.stringify({
      success: true,
      data: parseResult,
      tokens_used: {
        prompt_tokens: usage.prompt_tokens,
        completion_tokens: usage.completion_tokens,
        total_tokens: usage.total_tokens,
      },
      cost_estimate_usd: (usage.total_tokens / 1_000_000) * 0.003, // rough estimate for multimodal
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (error) {
    console.error("receipt-vision error:", error);
    return new Response(JSON.stringify({
      success: false,
      error: error.message ?? "Internal error",
      tokens_used: null,
    }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});