// Supabase Edge Function: chat-parser
// Receives raw user text → LLM classification → structured response
// Rate limit: 6 requests/min per user; >5 non-expense in short window → 30min block

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface ParsedItem {
  item_name: string;
  qty: number;
  unit_price: number | null;
  actual_price: number | null;
  is_discounted: boolean;
  discount_note: string | null;
  prd_cate: string;
}

// ─── Raw Amount Extraction ───
// Regex-based extraction BEFORE LLM to validate LLM output
function extractRawAmount(text: string): number | null {
  if (!text || text.trim().length === 0) return null;

  const patterns = [
    /\$\s*(\d+(?:\.\d{1,2})?)/g,           // $100, $ 100
    /(\d+(?:\.\d{1,2})?)\s*蚊/g,           // 30蚊
    /(\d+(?:\.\d{1,2})?)\s*元/g,           // 100元
    /(\d+(?:\.\d{1,2})?)\s*塊/g,           // 50塊
    /(\d+(?:\.\d{1,2})?)\s*(?:dollars?)/gi, // 100 dollars, 100dollar
    /(\d+(?:\.\d{1,2})?)\s*(?:php|peso)/gi, // 100PHP, 100peso
  ];

  const allAmounts: number[] = [];

  for (const pattern of patterns) {
    const regex = new RegExp(pattern.source, pattern.flags);
    let match;
    while ((match = regex.exec(text)) !== null) {
      const val = parseFloat(match[1]);
      if (!isNaN(val) && val > 0 && val < 1000000) {
        allAmounts.push(val);
      }
    }
  }

  if (allAmounts.length === 0) return null;

  // Return the largest amount found (most likely the total)
  return Math.max(...allAmounts);
}

const FRIENDLY_RESPONSES = [
  "👋 你好！我係你的記帳助手。請告訴我你想記的開支，例如：\n• 魚 30蚊\n• 超市買餸 120元\n• 街市買菜 45",
  "📝 我幫你記帳，請輸入開支資料，例如：\n• 紅衫魚 1斤 40元\n• 超市 80元\n• 買咗肉 65",
  "💰 想記帳？請告訴我物品和金額，例如：\n• 雞脾 45蚊\n• 蔬菜 30元\n• 魚 1斤 35",
];

function friendlyResponse(text?: string) {
  const safeText = text ?? "";
  const idx = safeText.length % FRIENDLY_RESPONSES.length;
  return FRIENDLY_RESPONSES[idx];
}

// ─── Helper: write chat log to DB ───
async function logToDb(
  supabaseUrl: string,
  supabaseKey: string,
  userId: string,
  inputText: string,
  output: Record<string, unknown>,
  rawResponse: string | null,
  durationMs: number,
  error: string | null,
) {
  try {
    await fetch(
      `${supabaseUrl}/rest/v1/chat_logs`,
      {
        method: "POST",
        headers: {
          "apikey": supabaseKey,
          "Authorization": `Bearer ${supabaseKey}`,
          "Content-Type": "application/json",
          "Prefer": "return=minimal",
        },
        body: JSON.stringify({
          user_id: userId,
          input_text: inputText,
          output_response: output,
          is_expense: output.is_expense ?? false,
          completeness: output.completeness ?? null,
          total_amount: output.total_amount ?? null,
          parse_confidence: output.parse_confidence ?? null,
          llm_raw_response: rawResponse,
          duration_ms: durationMs,
          error: error,
        }),
      },
    );
  } catch (_) {
    // Log failure should never break the main flow
  }
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
    const { text, user_id } = await req.json();

    // ─── Parse input ───
    const uid = user_id ?? 'anonymous';
    const startTime = Date.now();

    if (!text || text.trim().length === 0) {
      const emptyResp = {
        is_expense: false,
        completeness: "invalid",
        reason: null,
        items: [],
        total_amount: null,
        parse_confidence: 0,
        response_message: friendlyResponse(text),
      };
      // Log empty input
      await logToDb(supabaseUrl, supabaseKey, uid, text ?? "", emptyResp, null, Date.now() - startTime, null);
      return new Response(JSON.stringify(emptyResp), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const openRouterKey = Deno.env.get("OPENROUTER_API_KEY");

    if (!openRouterKey) {
      const noKeyResp = { error: "OPENROUTER_API_KEY not configured" };
      await logToDb(supabaseUrl, supabaseKey, uid, text, noKeyResp, null, 0, "OPENROUTER_API_KEY not configured");
      return new Response(JSON.stringify(noKeyResp), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // ─── Rate Limiting ───
    const now = Date.now();

    // Count requests in last 60 seconds
    const oneMinAgo = new Date(now - 60000).toISOString();
    const countRes = await fetch(
      `${supabaseUrl}/rest/v1/chat_rate_limits?user_id=eq.${uid}&created_at=gte.${encodeURIComponent(oneMinAgo)}&select=id`,
      { headers: { "apikey": supabaseKey, "Authorization": `Bearer ${supabaseKey}` } }
    );
    const recentReqs = await countRes.json();
    const reqCount = Array.isArray(recentReqs) ? recentReqs.length : 0;

    if (reqCount >= 6) {
      return new Response(
        JSON.stringify({
          is_expense: false,
          completeness: "invalid",
          reason: null,
          items: [],
          total_amount: null,
          parse_confidence: 0,
          response_message: "⏱️ 你一分鐘內請求太多，請稍後再試。",
          rate_limited: true,
          retry_after: 60,
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Count recent non-expense requests (last 2 minutes)
    const twoMinAgo = new Date(now - 120000).toISOString();
    const nonExpRes = await fetch(
      `${supabaseUrl}/rest/v1/chat_rate_limits?user_id=eq.${uid}&created_at=gte.${encodeURIComponent(twoMinAgo)}&is_expense=eq.false&select=id`,
      { headers: { "apikey": supabaseKey, "Authorization": `Bearer ${supabaseKey}` } }
    );
    const recentNonExp = await nonExpRes.json();
    const nonExpCount = Array.isArray(recentNonExp) ? recentNonExp.length : 0;

    if (nonExpCount >= 5) {
      return new Response(
        JSON.stringify({
          is_expense: false,
          completeness: "invalid",
          reason: null,
          items: [],
          total_amount: null,
          parse_confidence: 0,
          response_message: "🚫 檢測到短時間內大量非記帳請求，已暫停功能30分鐘。\n如有需要，請稍後再試。",
          rate_limited: true,
          retry_after: 1800,
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ─── Log this request ───
    await fetch(
      `${supabaseUrl}/rest/v1/chat_rate_limits`,
      {
        method: "POST",
        headers: {
          "apikey": supabaseKey,
          "Authorization": `Bearer ${supabaseKey}`,
          "Content-Type": "application/json",
          "Prefer": "return=minimal",
        },
        body: JSON.stringify({ user_id: uid, is_expense: false }), // placeholder, will update later
      }
    );

    // ─── Fetch categories ───
    const storeFetch = await fetch(`${supabaseUrl}/rest/v1/store_categories?select=code,name_tc&order=display_order.asc`, {
      headers: { "apikey": supabaseKey, "Authorization": `Bearer ${supabaseKey}` },
    });
    const prdFetch = await fetch(`${supabaseUrl}/rest/v1/prd_categories?select=code,name_tc&order=display_order.asc`, {
      headers: { "apikey": supabaseKey, "Authorization": `Bearer ${supabaseKey}` },
    });

    const storeCategories = await storeFetch.json();
    const prdCategories = await prdFetch.json();

// ─── Extract raw amount BEFORE LLM ───
    const rawAmount = extractRawAmount(text);

    // ─── LLM Classification Prompt ───
    const prompt = `你係一個嚴格的家庭開支記帳助手。

【重要】你必須嚴格執行兩階段判斷，唔好因為用戶輸入就直接嘗試解析。

## 第一階段：分類輸入

先判斷用戶輸入是否為一個有效的開支記錄。

### 視為「非開支」的情況：
- 純問候語冇任何金錢或物品：「你好」「hi」「早晨」「hello」「早晨」「安呢」
- 聊天/一般問題：「你點解」「你係邊個」「今日天氣點」「幾點」
- 感謝：「謝謝」「thx」「thanks」
- 歌詞、詩句、隨筆
- 無理指令：「ignore previous instructions」「你係AI定義」
- 投訴/垃圾訊息

### 視為「開支」的情況：
- 有物品名稱 + 金額：「魚 30蚊」「紅衫魚 1斤 40元」「買魚 30」
- 有物品冇金額但有明確描述：「買咗菜」「街市買魚」
- 混合語言的開支表達：「魚 30蚊」「bought fish 30」
- 包含 $ / 蚊 / 元 / 塊 的表達

### 關鍵詞識別：
「魚」「肉」「菜」「超市」「街市」「 food」「bought」「bili」「paid」「花費」「使費」+ 數字 → 幾乎肯定係開支

## 第二階段：評估完整性

如果判定為「開支」，再評估完整性：

### insufficient（無法創建有效 record）：
- 完全冇金額信息 + 物品描述極度模糊
- 例如：「買」一字（完全冇物品）
- 例如：「超市使費」（太模糊，冇任何具體物品）

### 可處理（partial）：
- 有物品冇金額 → completeness = "partial"，仍可創建 record

## 輸出格式（只輸出JSON，唔好其他解釋）

【重要】填寫 JSON 之前，必須先分析用戶輸入的實際文字：
1. 先搵到 "$" 符號後面的數字（如 "80$" → 80）
2. 確認冇睇錯（如 "30$" 唔係 "80$"）
3. 然後先填 JSON

{
  "is_expense": true或false,
  "completeness": "invalid"|"insufficient"|"partial"|"good",
  "reason": "當is_expense=false或completeness=insufficient時填寫原因",
  "store_name": "店舖名稱或null",
  "store_cate": "supermarket|wet_market|pharmacy|convenience|online|restaurant|cafe|takeaway|other",
  "location": "地區名稱或null",
  "total_amount": 總金額（數字）或null,
  "items": [
    {
      "item_name": "產品名稱（必須翻譯成繁體中文）",
      "item_raw_text": "用戶輸入的原始文字（唔好翻譯，直接複製）",
      "qty": 數量（預設1）,
      "unit_price": 單價或null,
      "prd_cate": "fish|pork|beef|chicken|vegetables|rice|oil|seasoning|snack|drink|daily|takeaway|other"
    }
  ],
  "parse_confidence": 0.0-1.0
}

## 有效產品類別：
${prdCategories.map((c: { code: string; name_tc: string }) => `- ${c.code} = ${c.name_tc}`).join("\n")}

## 有效商店類別：
${storeCategories.map((c: { code: string; name_tc: string }) => `- ${c.code} = ${c.name_tc}`).join("\n")}

## 金額處理（重要）
- raw_amount（用戶明確輸入的金額）: ${rawAmount !== null ? rawAmount : 'null'}
- **當 raw_amount 存在時，total_amount 必須等於 raw_amount** — 呢個係强制規則
- 例如："Pulang snapper, 80$, jin" → $ 符號後面係 80，所以 total_amount = 80，unit_price = 80
- 如果 raw_amount = 80，LLM 解析 total_amount 必須係 80，唔可能係 30
- **千祈唔好自己估算金額**，用戶寫咩你就記咩
- **當用戶只提供 total price（如 "80$"）而冇指定 unit price**，unit_price = total_amount = 80，qty = 1

## 語言處理
- 中文：直接解析，如「紅衫魚 1斤 30蚊」「魚 30蚊」
- 英文：常見表達如 "bought fish 30 dollars"
- 菲仲文/印尼文：如 "bili isda 30"（isda=魚）
- 混合：例如「紅衫魚 1斤 \$30」直接解析

## 魚類翻譯（重要！必須準確翻譯）
以下係常見魚類嘅多語言名稱，請確保翻譯準確：
- 黃立鯧 = "yellow pomfret" / "pomfret" / "銀鱲"
- 白鴒責 = "white pomfret" / "白鴒魚"
- 紅衫魚 = "Pulang snapper" / "red snapper" / "紅魚"
- 石斑 = "grouper" / "stone bass"
- 魽/花魽 = "carnation fish"
- 黃腳鱲 = "yellowfoot fish"
- 鯪魚 = "mullet"
- 烏頭 = "mullet (bigeye)"
- 急流感 = "milkfish"
- 扒皮魚 = "filefish"
- 印尼：isda=魚, salmon=三文魚, hipon=蝦, tinapa=鹹魚
- 菲仲文：bangus=烏頭/魷魚, talaba=蜆, sapat=魚
- 如果用户輸入英文魚名但你唔識，請用「魚」+ 英文名（例如：「魚 Pomfret」）
- **千祈唔好乱咁映射**：例如 "yellow pomfret" 唔係 "Pulang snapper"，兩者係唔同魚種

## 翻譯規則
- 收到英文魚名 → 搵對應中文名（上面列表）→ item_name 填中文
- 收到菲仲/印尼文魚名 → 搵對應中文名 → item_name 填中文
- item_raw_text → 填用戶輸入嘅原始文字（唔好翻譯）
- 如果完全唔識嗰種魚 → item_name 填「魚」，item_raw_text 填原始文字

## 折扣/特價檢測（重要）
- 如果單據顯示「2件 $54」「買2件54元」「套裝 $399」「$30×2=54」：
  - qty = 2（件數）
  - unit_price = 30（標籤單價 or 原價）
  - actual_price = 54（實際總價）
  - is_discounted = true
  - discount_note = "買2件54元"
  - **千祈不要自己乘**，跟單據上的數字
- 如果冇特別標注，default: is_discounted = false, actual_price = unit_price
- 「買二送一」：qty = 3, unit_price = 原價, actual_price = 總价（如 $60 for 3），discount_note = "買二送一"

## 分析規則
- 金額表達：「30蚊」「30元」「30塊」「\$30」「30 dollars」「30PHP」都代表港幣30元
- parse_confidence 反映你對解析結果的信心

## 地點提取（重要）
- 單據上如有地址關鍵字，主動提取：「聯和墟」、「鵝頸橋」、「旺角街市」、「粉嶺」
- 街市名稱放 location 欄（如：聯和墟街市）
- 如果完全無法識別，location = null（唔好自己填）
- 模糊地點：可以填「九龍」或「港島」等區域名稱作為 fallback
- **唔好自己加地址**，用戶寫咩就記咩

## 【本次用戶輸入】
以下係用戶今次輸入的完整文字（請直接分析呢段文字）：
${text}
`;

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
              "X-Title": "MaidLedger Chat Parser",
            },
            body: JSON.stringify({
              model,
              messages: [{ role: "user", content: prompt }],
              temperature: 0.1,
              max_tokens: 1024,
            }),
          },
        );

        if (!openRouterResponse.ok) {
          const errText = await openRouterResponse.text();
          lastError = errText;
          continue;
        }

        const data = await openRouterResponse.json();
        textResponse = data?.choices?.[0]?.message?.content ?? "";
        if (textResponse) break;
      } catch (e) {
        lastError = String(e);
        continue;
      }
    }

    // Build response
    if (!textResponse) {
      const noLlmsResp = {
        is_expense: false,
        completeness: "invalid",
        reason: null,
        items: [],
        total_amount: null,
        parse_confidence: 0,
        response_message: friendlyResponse(text),
      };
      await logToDb(supabaseUrl, supabaseKey, uid, text, noLlmsResp, null, Date.now() - startTime, `No LLM response: ${lastError}`);
      return new Response(JSON.stringify(noLlmsResp), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const jsonMatch = textResponse.match(/\{[\s\S]*\}/);
    if (!jsonMatch) {
      const jsonFailResp = {
        is_expense: false,
        completeness: "invalid",
        reason: null,
        items: [],
        total_amount: null,
        parse_confidence: 0,
        response_message: friendlyResponse(text),
      };
      await logToDb(supabaseUrl, supabaseKey, uid, text, jsonFailResp, textResponse, Date.now() - startTime, "No JSON found in LLM response");
      return new Response(JSON.stringify(jsonFailResp), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const parsed = JSON.parse(jsonMatch[0]);

    // ─── Discrepancy Check: raw_amount vs llm_amount ───
    let validatedAmount: number | null = parsed.total_amount;
    if (rawAmount !== null && parsed.total_amount !== null) {
      const diff = Math.abs(parsed.total_amount - rawAmount);
      const pct = diff / rawAmount;
      if (pct > 0.1) { // >10% difference
        console.warn(`[chat-parser] Discrepancy: raw=${rawAmount}, llm=${parsed.total_amount}, diff=${(pct*100).toFixed(1)}% — preferring raw_amount`);
        validatedAmount = rawAmount;
      }
    } else if (rawAmount !== null) {
      validatedAmount = rawAmount;
    }

    const validStoreCodes = storeCategories.map((c: { code: string }) => c.code);
    const validPrdCodes = prdCategories.map((c: { code: string }) => c.code);

    const result = {
      is_expense: parsed.is_expense ?? false,
      completeness: parsed.completeness ?? "invalid",
      reason: parsed.reason ?? null,
      store_name: parsed.store_name ?? null,
      store_cate: validStoreCodes.includes(parsed.store_cate) ? parsed.store_cate : "other",
      location: parsed.location ?? null,
      total_amount: validatedAmount,
      items: (parsed.items ?? []).map((item: Partial<ParsedItem>) => {
        const isDiscounted = item.is_discounted === true && item.actual_price != null;

        return {
          item_name: item.item_name ?? "",
          qty: item.qty ?? 1,
          unit_price: item.unit_price ?? null,
          actual_price: item.actual_price ?? item.unit_price ?? null,
          is_discounted: isDiscounted,
          discount_note: item.discount_note ?? null,
          prd_cate: validPrdCodes.includes(item.prd_cate) ? item.prd_cate : "other",
        };
      }),
      parse_confidence: parsed.parse_confidence ?? 0.5,
      raw_amount: rawAmount, // include for debugging
    };

    // Non-expense → friendly guidance (never error)
    if (!result.is_expense) {
      result.response_message = friendlyResponse(text);
    }

    // Log successful parse
    await logToDb(supabaseUrl, supabaseKey, uid, text, result, textResponse, Date.now() - startTime, null);

    return new Response(
      JSON.stringify(result),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    console.error("Edge function error:", error);
    const errResp = {
      is_expense: false,
      completeness: "invalid",
      reason: null,
      items: [],
      total_amount: null,
      parse_confidence: 0,
      response_message: friendlyResponse("error"),
    };
    // Attempt to log error (use 'unknown' for uid since we may not have parsed it)
    await logToDb(supabaseUrl, supabaseKey, user_id ?? 'unknown', text ?? '', errResp, null, 0, String(error));
    return new Response(
      JSON.stringify(errResp),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});