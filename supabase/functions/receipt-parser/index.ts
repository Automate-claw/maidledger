// Supabase Edge Function: receipt-parser
// Receives raw OCR text, returns structured receipt data via OpenRouter

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface ParsedItem {
  item_name: string;
  item_raw_text: string;
  qty: number;
  unit_price: number | null;
  prd_cate: string;
}

// In-memory cache for categories (1 hour TTL)
let categoriesCache: {
  storeCategories: { code: string; name_tc: string }[];
  prdCategories: { code: string; name_tc: string }[];
  fetchedAt: number;
} | null = null;

const CACHE_TTL_MS = 60 * 60 * 1000; // 1 hour

async function getCategories(supabaseUrl: string, supabaseKey: string) {
  const now = Date.now();
  if (categoriesCache && (now - categoriesCache.fetchedAt) < CACHE_TTL_MS) {
    return categoriesCache;
  }

  // Fetch from DB
  const storeFetch = await fetch(`${supabaseUrl}/rest/v1/store_categories?select=code,name_tc&order=display_order.asc`, {
    headers: {
      "apikey": supabaseKey,
      "Authorization": `Bearer ${supabaseKey}`,
    },
  });

  const prdFetch = await fetch(`${supabaseUrl}/rest/v1/prd_categories?select=code,name_tc&order=display_order.asc`, {
    headers: {
      "apikey": supabaseKey,
      "Authorization": `Bearer ${supabaseKey}`,
    },
  });

  const storeCategories = await storeFetch.json();
  const prdCategories = await prdFetch.json();

  categoriesCache = { storeCategories, prdCategories, fetchedAt: now };
  return categoriesCache;
}

// Health check endpoint (for cron warmer)
serve(async (req) => {
  if (req.method === "GET" && new URL(req.url).pathname.endsWith("health")) {
    return new Response(
      JSON.stringify({ status: "ok", timestamp: Date.now() }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { raw_text, reconstructed_text } = await req.json();

    if (!raw_text || raw_text.trim().length === 0) {
      return new Response(
        JSON.stringify({ error: "raw_text is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const openRouterKey = Deno.env.get("OPENROUTER_API_KEY");

    if (!openRouterKey) {
      return new Response(
        JSON.stringify({ error: "OPENROUTER_API_KEY not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Fetch categories dynamically from DB
    const cats = await getCategories(supabaseUrl, supabaseKey);
    const STORE_CATEGORIES = cats.storeCategories;
    const PRD_CATEGORIES = cats.prdCategories;

    // raw_text = OCR raw text
    // reconstructed_text = Row-Reconstructed text (left|right format)
    const rawOcrText = raw_text.trim();
    const reconstructedText = (reconstructed_text || "").trim();

    // Build prompt with dynamic category lists
    const prompt = `你係一個香港收據分析助手。請分析以下OCR文字，提取結構化資料。

【重要】輸出必須係「純」JSON，唔好包含任何URL編碼、HTML實體、Markdown code blocks或其他特殊格式。所有文字必須係可以直接閱讀的繁體中文。

## OCR 原始文字（未整理）
${rawOcrText}

${reconstructedText ? `## 行內重構文字（同一行以「 | 」分隔左右兩欄）
呢個係重構後嘅結構，每一行嘅「 | 」左邊係項目名稱，右邊係價格。請特別注意呢個格式黎配對 item 同 price！
${reconstructedText}
` : ""}

## 有效商店類別（請從以下選擇 store_cate）：
${STORE_CATEGORIES.map((c) => `- ${c.code} = ${c.name}`).join("\n")}

## 有效產品類別（請從以下選擇 prd_cate）：
${PRD_CATEGORIES.map((c) => `- ${c.code} = ${c.name}`).join("\n")}

## 香港地區名稱（用於校正 location）：
中環、上環、西環、堅尼地城、香港仔、薄扶林、山頂、灣仔、銅鑼灣、跑馬地、北角、鰂魚涌、筲箕灣、西灣河、柴灣、九龍城、九龍塘、旺角、太子、深水埗、長沙灣、荔枝角、美孚、黃大仙、彩虹、觀塘、牛頭角、九龍灣、油塘、藍田、鯉魚門、新蒲崗、沙田、大圍、火炭、馬鞍山、科學園、大埔、上水、粉嶺、元朗、天水圍、屯門、荃灣、葵涌、青衣、將軍澳、坑口、調景嶺、西貢、清水灣、其他

## 輸出格式（只輸出JSON）：
{
  "store_name": "店舖名稱",
  "store_cate": "有效的store_cate code",
  "location": "地區名稱",
  "total_amount": 數字或null,
  "transaction_date": "YYYY-MM-DD格式或null",
  "items": [
    {
      "item_name": "產品名稱",
      "item_raw_text": "呢行嘅原始OCR文字",
      "qty": 數量,
      "unit_price": 單價或null,
      "prd_cate": "有效的prd_cate code"
    }
  ],
  "parse_confidence": 0.0-1.0
}

## 分析規則

### store_cate 選擇
- 有超市名稱（惠康、百佳、AEON、華潤、U購）→ "supermarket"
- 街邊市集/菜市場/魚檔/肉檔 → "wet_market"
- 藥房（藥房、成藥） → "pharmacy"
- 7-11 OK 便利店 → "convenience"
- 網購平台 → "online"
- 茶餐廳/餐廳/咖啡店 → 從上述有效列表選擇
- 完全無法判斷 → "other"

### item + price 配對規則
- 如果有「Row-Reconstructed」格式，以「 | 」分隔黎配對左邊item名稱、右邊價格
- 如果同一行有多於2個 block（如 item | qty | price）， interpret accordingly
- 如果 OCR 碎片化導致 item 同 price 分離，嘗試用以下方法：
  1. 找「項目總計」或「TOTAL」附近明確的價格（呢個係 total_amount）
  2. 如果 item_raw_text 入面有明確數量（如「雞脾 x2」），從 item 名稱推斷
  3. 如果實在無法配對，unit_price 設為 null，item_raw_text 填寫完整行文字

### location 校正
- OCR 可能把「灣仔」讀成「灣貨」等，請對照香港地區名稱列表自動校正
- 如果讀取到的地址包含上述任何地區名稱，自動更正

### 其他規則
- 金額唔需要加$符號，直接填數字
- unit_price 必須係有效數字，無法確認時設為 null（唔好乱填）
- 如果搵唔到 store_name，輸入「未知商戶」
- transaction_date 優先從明確的日期欄位讀取
- parse_confidence 反映你對整體解析結果的信心程度`;

    // Call OpenRouter API
    const models = [
      "deepseek/deepseek-chat-v3.1",
      "qwen/qwen3-8b",
    ];

    let lastError = "";
    let textResponse = "";

    for (const model of models) {
      try {
        const openRouterResponse = await fetch(
          "https://openrouter.ai/api/v1/chat/completions",
          {
            method: "POST",
            headers: {
              "Authorization": `Bearer ${openRouterKey}`,
              "Content-Type": "application/json",
              "HTTP-Referer": "https://maidledger.app",
              "X-Title": "MaidLedger Receipt Parser",
            },
            body: JSON.stringify({
              model,
              messages: [
                {
                  role: "user",
                  content: prompt,
                },
              ],
              temperature: 0.2,
              max_tokens: 2048,
            }),
          },
        );

        if (!openRouterResponse.ok) {
          const errText = await openRouterResponse.text();
          console.error(`OpenRouter API error (${model}):`, errText);
          lastError = errText;
          continue;
        }

        const data = await openRouterResponse.json();
        textResponse = data?.choices?.[0]?.message?.content ?? "";

        if (textResponse) break;
      } catch (e) {
        console.error(`Exception calling ${model}:`, e);
        lastError = String(e);
        continue;
      }
    }

    if (!textResponse) {
      return new Response(
        JSON.stringify({ error: "All LLM providers failed", details: lastError }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Parse JSON from LLM response
    const jsonMatch = textResponse.match(/\{[\s\S]*\}/);
    if (!jsonMatch) {
      return new Response(
        JSON.stringify({
          store_name: null,
          store_cate: "other",
          location: null,
          total_amount: null,
          transaction_date: null,
          items: [],
          parse_confidence: 0,
          raw_text: raw_text,
          error: "No JSON found in LLM response",
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const parsed = JSON.parse(jsonMatch[0]);

    // Validate store_cate against valid codes
    const validStoreCodes = STORE_CATEGORIES.map((c) => c.code);
    const validPrdCodes = PRD_CATEGORIES.map((c) => c.code);

    const result = {
      store_name: parsed.store_name ?? null,
      store_cate: validStoreCodes.includes(parsed.store_cate) ? parsed.store_cate : "other",
      location: parsed.location ?? null,
      total_amount: parsed.total_amount ?? null,
      transaction_date: parsed.transaction_date ?? null,
      items: (parsed.items ?? []).map((item: Partial<ParsedItem>) => ({
        item_name: item.item_name ?? "",
        item_raw_text: item.item_raw_text ?? "",
        qty: item.qty ?? 1,
        unit_price: item.unit_price ?? null,
        prd_cate: validPrdCodes.includes(item.prd_cate) ? item.prd_cate : "other",
      })),
      parse_confidence: parsed.parse_confidence ?? 0.5,
    };

    return new Response(
      JSON.stringify({ ...result, raw_text }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    console.error("Edge function error:", error);
    return new Response(
      JSON.stringify({ error: error.message ?? "Internal error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});