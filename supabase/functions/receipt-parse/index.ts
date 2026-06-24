// ══════════════════════════════════════════════════════════════════════════════
// receipt-parse — LLM parsing for receipt OCR text
// Input:  { ocr_raw_text, ocr_reconstructed?, raw_text? }
// Output: { store_name, store_cate, location, total_amount, transaction_date,
//           items[], parse_confidence }
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
  const jsonMatch = text.match(/\{[\s\S]*\}/);
  if (!jsonMatch) throw new Error("No JSON found in LLM response");
  return JSON.parse(jsonMatch[0]);
}

// ── LLM call ────────────────────────────────────────────────────────────────
async function callLLMParse(rawOcrText: string, reconstructedText: string, supabaseUrl: string, supabaseKey: string) {
  const openRouterKey = Deno.env.get("OPENROUTER_API_KEY") ?? "";
  if (!openRouterKey) throw new Error("OPENROUTER_API_KEY not configured");

  const cats = await getCategories(supabaseUrl, supabaseKey);
  const STORE_CATEGORIES = cats.storeCategories;
  const PRD_CATEGORIES = cats.prdCategories;

  const prompt = `你係一個香港收據分析助手。請分析以下OCR文字，提取結構化資料。

【重要】輸出必須係「純」JSON，唔好包含任何URL編碼、HTML實體、Markdown code blocks或其他特殊格式。所有文字必須係可以直接閱讀的繁體中文。

## OCR 原始文字（未整理）
${rawOcrText}

${reconstructedText ? `## 行內重構文字（同一行以「 | 」分隔左右兩欄）
呢個係重構後嘅結構，每一行嘅「 | 」左邊係項目名稱，右邊係價格。請特別注意呢個格式黎配對 item 同 price！
${reconstructedText}
` : ""}

## 有效商店類別（請從以下選擇 store_cate）：
${STORE_CATEGORIES.map((c) => `- ${c.code} = ${c.name_tc}`).join("\n")}

## 有效產品類別（請從以下選擇 prd_cate）：
${PRD_CATEGORIES.map((c) => `- ${c.code} = ${c.name_tc}`).join("\n")}

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
      "item_name": "產品的原始完整名稱",
      "extracted_brand": "品牌名稱，無則填 null",
      "extracted_name": "去除品牌、容量、店鋪特異字眼後的純產品核心名稱",
      "extracted_spec": "規格容量，無則填 null",
      "item_raw_text": "原始OCR行文字",
      "qty": 數量,
      "unit_price": 單價或null,
      "prd_cate": "有效的prd_cate code",
      "standard_name": "標準化產品名稱（如：牛肉片、菜心、維他豆奶）",
      "normalized_unit_price": 數字或null,
      "unit_for_normalized": "標準單位（如：斤、盒、100g、件）",
      "is_fresh_food": true或false,
      "confidence_score": 0.0-1.0
    }
  ],
  "parse_confidence": 0.0-1.0
}

### 品牌/名稱/規格 拆分規則
- extracted_brand：品牌名（如收據上寫「759阿信屋」，就填「759阿信屋」）
- extracted_name：去除品牌同規格之後的純產品通用名稱
- extracted_spec：容量、尺寸、包裝數量
- 如果無法確定某個欄位，填 null

### 標準化欄位計算規則（最重要）
- **standard_name**：LLM 自動生成的標準化名稱，用於跨家庭比較。例如：
  - "VITA SOY REG 250ML 6PK" → "維他純豆奶"
  - "美國牛肉片 1磅 $85" → "牛肉片"
  - "街市菜心 1斤 $14" → "菜心"
- **normalized_unit_price**：將 unit_price 換算成「每標準單位」的價格。例如：
  - "$20.5 / 6盒250ml" → normalized_unit_price = 20.5 / 6 = 3.41（每盒）
  - "$85 / 1磅" → normalized_unit_price = 85（每磅）
  - "$14 / 1斤" → normalized_unit_price = 14（每斤）
  - "$25 / 1公升" → normalized_unit_price = 25（每公升）→ 需換算成每100ml = 2.5
- **unit_for_normalized**：用於 normalized_unit_price 的標準單位，例如：
  - 包裝食品："盒"、"罐"、"包"、"件"
  - 生鮮肉類："斤"、"磅"、"両"
  - 液體飲料："100ml"、"公升"
  - 乾貨/糧油："100g"、"斤"、"公斤"
- **is_fresh_food**：
  - true：街市/濕市場購買的生鮮（蔬菜、肉類、海魚、豆腐、雞蛋）
  - false：超市包裝食品、糧油罐頭、清潔用品

### is_fresh_food 判斷規則
以下情況設為 true：
- 購買地點係「街市」（wet_market）或「鮮活食品店」
- 產品名稱包含：菜心、白菜、西蘭花、肉片、魚、豆腐、雞蛋、鮮肉
- 沒有固定包裝、論斤論両銷售的

以下情況設為 false：
- 超市包裝食品（維他、益力多、品客、合味道等）
- 糧油罐頭（鹽、糖、油、醬油、罐頭）
- 清潔用品（洗潔精、洗衣粉、廁紙）
- 有固定包裝、條碼的加工食品

### item + price 配對規則
- 如果有「Row-Reconstructed」格式，以「 | 」分隔黎配對
- 如果 OCR 碎片化導致 item 同 price 分離，嘗試靠「TOTAL」附近價格推斷
- 如果 item 有 quantity > 1（例如「×3」），unit_price 係總價，需除以 qty

### location 校正
- OCR 可能把「灣仔」讀成「灣貨」等，請對照香港地區名稱列表自動校正

### 其他規則
- 金額唔需要加$符號，直接填數字
- unit_price 必須係有效數字，無法確認時設為 null
- normalized_unit_price 必須係有效數字，無法確認時設為 null
- confidence_score 反映對整體解析結果的信心程度，低於 0.5 嘅項目唔應該出現

  const models = ["deepseek/deepseek-chat-v3.1", "qwen/qwen3-8b"];
  let lastError = "";
  let textResponse = "";

  for (const model of models) {
    try {
      const resp = await fetch("https://openrouter.ai/api/v1/chat/completions", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${openRouterKey}`,
          "Content-Type": "application/json",
          "HTTP-Referer": "https://maidledger.app",
          "X-Title": "MaidLedger Receipt Parser",
        },
        body: JSON.stringify({
          model,
          messages: [{ role: "user", content: prompt }],
          temperature: 0.2,
          max_tokens: 2048,
        }),
      });
      if (!resp.ok) {
        lastError = await resp.text();
        continue;
      }
      const data = await resp.json();
      textResponse = data?.choices?.[0]?.message?.content ?? "";
      if (textResponse) break;
    } catch (e) {
      lastError = String(e);
      continue;
    }
  }
  if (!textResponse) throw new Error(`LLM failed for all models. Last error: ${lastError}`);
  return parseJsonResponse(textResponse);
}

// ─────────────────────────────────────────────────────────────────────────────
serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "";

    let body: any;
    try { body = await req.json(); } catch { body = {}; }

    const ocrRawText = (body.ocr_raw_text || body.raw_text || "").trim();
    const reconstructedText = (body.ocr_reconstructed || "").trim();

    if (!ocrRawText) {
      return new Response(JSON.stringify({ error: "ocr_raw_text is required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const parseResult = await callLLMParse(ocrRawText, reconstructedText, supabaseUrl, supabaseKey);

    return new Response(JSON.stringify({
      success: true,
      data: parseResult,
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (error) {
    console.error("receipt-parse error:", error);
    return new Response(JSON.stringify({
      success: false,
      error: error.message ?? "Internal error",
    }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});