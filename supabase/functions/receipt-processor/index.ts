// Supabase Edge Function: receipt-processor
// Background job: picks up pending receipts → LLM parse → product matching → price_history
// Triggered by cron every 1 minute

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

interface ReceiptRow {
  id: string;
  helper_id: string;
  employer_id: string | null;
  relation_id: string | null;
  ocr_raw_text: string;
  ocr_reconstructed: string | null;
  amount: string | null;
}

// In-memory cache
let categoriesCache: {
  storeCategories: { code: string; name_tc: string }[];
  prdCategories: { code: string; name_tc: string }[];
  fetchedAt: number;
} | null = null;

const CACHE_TTL_MS = 60 * 60 * 1000;
const HIGH_AMOUNT_THRESHOLD = 500; // HKD

async function getCategories(supabaseUrl: string, supabaseKey: string) {
  const now = Date.now();
  if (categoriesCache && (now - categoriesCache.fetchedAt) < CACHE_TTL_MS) {
    return categoriesCache;
  }
  const storeFetch = await fetch(`${supabaseUrl}/rest/v1/store_categories?select=code,name_tc&order=display_order.asc`, {
    headers: { "apikey": supabaseKey, "Authorization": `Bearer ${supabaseKey}` },
  });
  const prdFetch = await fetch(`${supabaseUrl}/rest/v1/prd_categories?select=code,name_tc&order=display_order.asc`, {
    headers: { "apikey": supabaseKey, "Authorization": `Bearer ${supabaseKey}` },
  });
  categoriesCache = {
    storeCategories: await storeFetch.json(),
    prdCategories: await prdFetch.json(),
    fetchedAt: now,
  };
  return categoriesCache;
}

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

### item + price 配對規則
- 如果有「Row-Reconstructed」格式，以「 | 」分隔黎配對左邊item名稱、右邊價格
- 如果同一行有多於2個 block（如 item | qty | price）， interpret accordingly
- 如果 OCR 碎片化導致 item 同 price 分離，嘗試用以下方法：
  1. 找「項目總計」或「TOTAL」附近明確的價格（呢個係 total_amount）
  2. 如果 item_raw_text 入面有明確數量（如「雞脾 x2」），從 item 名稱推斷
  3. 如果實在無法配對，unit_price 設為 null，item_raw_text 填寫完整行文字

### location 校正
- OCR 可能把「灣仔」讀成「灣貨」等，請對照香港地區名稱列表自動校正

### 其他規則
- 金額唔需要加$符號，直接填數字
- unit_price 必須係有效數字，無法確認時設為 null
- transaction_date 優先從明確的日期欄位讀取
- parse_confidence 反映你對整體解析結果的信心程度`;

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
        body: JSON.stringify({ model, messages: [{ role: "user", content: prompt }], temperature: 0.2, max_tokens: 2048 }),
      });
      if (!resp.ok) { lastError = await resp.text(); continue; }
      const data = await resp.json();
      textResponse = data?.choices?.[0]?.message?.content ?? "";
      if (textResponse) break;
    } catch (e) {
      lastError = String(e);
      continue;
    }
  }

  if (!textResponse) throw new Error(`LLM failed: ${lastError}`);

  const jsonMatch = textResponse.match(/\{[\s\S]*\}/);
  if (!jsonMatch) throw new Error("No JSON in LLM response");
  return JSON.parse(jsonMatch[0]);
}

// Product matching helpers
function escapeIlike(str: string): string {
  return str.replace(/[%_\\]/g, "\\$&");
}

async function matchProduct(supabaseUrl: string, supabaseKey: string, itemName: string, prdCate: string | null): Promise<string | null> {
  // 1. Exact alias match
  const aliasResp = await fetch(
    `${supabaseUrl}/rest/v1/product_aliases?select=master_product_id&raw_name=eq.${encodeURIComponent(itemName)}&limit=1`,
    { headers: { "apikey": supabaseKey, "Authorization": `Bearer ${supabaseKey}` } }
  );
  const aliases = await aliasResp.json();
  if (aliases?.length > 0) return aliases[0].master_product_id;

  // 2. ILIKE keyword match
  const keywords = itemName.trim().split(/[\s　]+/).filter((k) => k.length > 1).slice(0, 3);
  if (keywords.length === 0) return null;

  const orParts = keywords.map((kw) => `canonical_name.ilike.%${escapeIlike(kw)}%`).join(",");
  const catFilter = prdCate && prdCate !== "other" ? `&prd_cate=eq.${prdCate}` : "";

  const mpResp = await fetch(
    `${supabaseUrl}/rest/v1/master_products?select=id&or=(${orParts})${catFilter}&limit=5`,
    { headers: { "apikey": supabaseKey, "Authorization": `Bearer ${supabaseKey}` } }
  );
  const products = await mpResp.json();
  if (products?.length > 0) {
    // Create alias for future
    await fetch(`${supabaseUrl}/rest/v1/product_aliases`, {
      method: "POST",
      headers: { "apikey": supabaseKey, "Authorization": `Bearer ${supabaseKey}`, "Content-Type": "application/json", "Prefer": "resolution=ignore-duplicates" },
      body: JSON.stringify({ raw_name: itemName, master_product_id: products[0].id, source: "ocr" }),
    });
    return products[0].id;
  }
  return null;
}

async function createMasterProduct(supabaseUrl: string, supabaseKey: string, name: string, prdCate: string): Promise<string> {
  // Create master product
  const mpResp = await fetch(`${supabaseUrl}/rest/v1/master_products`, {
    method: "POST",
    headers: { "apikey": supabaseKey, "Authorization": `Bearer ${supabaseKey}`, "Content-Type": "application/json", "Prefer": "return=representation" },
    body: JSON.stringify({ canonical_name: name.trim(), prd_cate: prdCate || "other", default_unit: "件" }),
  });
  const mp = await mpResp.json();
  const mpId = mp[0]?.id ?? mp?.id;
  if (!mpId) throw new Error("Failed to create master product");

  // Create alias
  await fetch(`${supabaseUrl}/rest/v1/product_aliases`, {
    method: "POST",
    headers: { "apikey": supabaseKey, "Authorization": `Bearer ${supabaseKey}`, "Content-Type": "application/json", "Prefer": "resolution=ignore-duplicates" },
    body: JSON.stringify({ raw_name: name.trim(), master_product_id: mpId, source: "ocr" }),
  });
  return mpId;
}

async function matchShop(supabaseUrl: string, supabaseKey: string, rawShopName: string, shopType: string | null): Promise<string | null> {
  // 1. Exact match in shop_aliases
  const aliasResp = await fetch(
    `${supabaseUrl}/rest/v1/shops?select=id&shop_aliases(raw_name.ilike.%${escapeIlike(rawShopName)}%)&limit=1`,
    { headers: { "apikey": supabaseKey, "Authorization": `Bearer ${supabaseKey}` } }
  );
  const shops = await aliasResp.json();
  if (shops?.length > 0) return shops[0].id;

  // 2. ILIKE match on canonical_name
  const nameResp = await fetch(
    `${supabaseUrl}/rest/v1/shops?select=id&canonical_name.ilike.%${escapeIlike(rawShopName)}%&limit=1`,
    { headers: { "apikey": supabaseKey, "Authorization": `Bearer ${supabaseKey}` } }
  );
  const shops2 = await nameResp.json();
  if (shops2?.length > 0) return shops2[0].id;

  return null;
}

// Main process function
async function processReceipt(receipt: ReceiptRow, supabaseUrl: string, supabaseKey: string): Promise<void> {
  // Mark as processing
  await fetch(`${supabaseUrl}/rest/v1/receipts?id=eq.${receipt.id}`, {
    method: "PATCH",
    headers: { "apikey": supabaseKey, "Authorization": `Bearer ${supabaseKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({ parse_status: "processing" }),
  });

  let parseResult: any;
  try {
    parseResult = await callLLMParse(
      receipt.ocr_raw_text || "",
      receipt.ocr_reconstructed || "",
      supabaseUrl,
      supabaseKey
    );
  } catch (e) {
    // LLM failed → mark failed
    await fetch(`${supabaseUrl}/rest/v1/receipts?id=eq.${receipt.id}`, {
      method: "PATCH",
      headers: { "apikey": supabaseKey, "Authorization": `Bearer ${supabaseKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ parse_status: "failed" }),
    });
    console.error(`Receipt ${receipt.id} LLM failed:`, e);
    return;
  }

  // Determine needs_review
  const confidence = parseResult.parse_confidence ?? 0;
  const amount = parseResult.total_amount ?? 0;
  const needsReview = confidence < 0.7 || amount > HIGH_AMOUNT_THRESHOLD;

  const validStoreCodes = (await getCategories(supabaseUrl, supabaseKey)).storeCategories.map((c) => c.code);
  const validPrdCodes = (await getCategories(supabaseUrl, supabaseKey)).prdCategories.map((c) => c.code);

  // Update receipt with parsed data
  const receiptUpdate: Record<string, any> = {
    store_name: parseResult.store_name ?? "未知商戶",
    store_cate: validStoreCodes.includes(parseResult.store_cate) ? parseResult.store_cate : "other",
    location: parseResult.location ?? null,
    amount: parseResult.total_amount ?? null,
    transaction_date: parseResult.transaction_date ?? null,
    parsed_data: JSON.stringify(parseResult),
    parse_confidence: confidence,
    needs_review: needsReview,
    parse_status: "parsed",
  };

  await fetch(`${supabaseUrl}/rest/v1/receipts?id=eq.${receipt.id}`, {
    method: "PATCH",
    headers: { "apikey": supabaseKey, "Authorization": `Bearer ${supabaseKey}`, "Content-Type": "application/json" },
    body: JSON.stringify(receiptUpdate),
  });

  // Insert receipt_items
  const items: any[] = parseResult.items ?? [];
  if (items.length > 0) {
    const itemRows = items.map((item) => ({
      receipt_id: receipt.id,
      item_name: item.item_name ?? "",
      item_raw_text: item.item_raw_text ?? "",
      qty: item.qty ?? 1,
      unit_price: item.unit_price ?? null,
      line_total: item.unit_price != null && item.qty != null ? item.unit_price * item.qty : null,
      prd_cate: validPrdCodes.includes(item.prd_cate) ? item.prd_cate : "other",
    }));

    await fetch(`${supabaseUrl}/rest/v1/receipt_items`, {
      method: "POST",
      headers: { "apikey": supabaseKey, "Authorization": `Bearer ${supabaseKey}`, "Content-Type": "application/json", "Prefer": "return=representation" },
      body: JSON.stringify(itemRows),
    });

    // Product matching + price_history
    for (const item of items) {
      try {
        let masterProductId = await matchProduct(supabaseUrl, supabaseKey, item.item_raw_text || item.item_name, item.prd_cate);
        if (!masterProductId) {
          masterProductId = await createMasterProduct(supabaseUrl, supabaseKey, item.item_name, item.prd_cate || "other");
        }

        // Bind to receipt_item
        const itemResp = await fetch(
          `${supabaseUrl}/rest/v1/receipt_items?select=id&receipt_id=eq.${receipt.id}&item_name=eq.${encodeURIComponent(item.item_name)}&limit=1`,
          { headers: { "apikey": supabaseKey, "Authorization": `Bearer ${supabaseKey}` } }
        );
        const itemRows2 = await itemResp.json();
        if (itemRows2?.length > 0) {
          await fetch(`${supabaseUrl}/rest/v1/receipt_items?id=eq.${itemRows2[0].id}`, {
            method: "PATCH",
            headers: { "apikey": supabaseKey, "Authorization": `Bearer ${supabaseKey}`, "Content-Type": "application/json" },
            body: JSON.stringify({ master_product_id: masterProductId }),
          });

          // Write price_history
          if (item.unit_price != null) {
            await fetch(`${supabaseUrl}/rest/v1/price_history`, {
              method: "POST",
              headers: { "apikey": supabaseKey, "Authorization": `Bearer ${supabaseKey}`, "Content-Type": "application/json" },
              body: JSON.stringify({
                master_product_id: masterProductId,
                location: parseResult.location,
                price: item.unit_price * (item.qty ?? 1),
                original_price: item.unit_price,
                unit: "件",
                source_receipt_id: receipt.id,
                recorded_at: receipt.transaction_date ?? new Date().toISOString().split("T")[0],
              }),
            });
          }
        }
      } catch (e) {
        console.error(`Product matching error for "${item.item_name}":`, e);
      }
    }
  }

  // Shop matching
  if (parseResult.store_name) {
    const shopId = await matchShop(supabaseUrl, supabaseKey, parseResult.store_name, parseResult.store_cate);
    if (shopId) {
      await fetch(`${supabaseUrl}/rest/v1/receipts?id=eq.${receipt.id}`, {
        method: "PATCH",
        headers: { "apikey": supabaseKey, "Authorization": `Bearer ${supabaseKey}`, "Content-Type": "application/json" },
        body: JSON.stringify({ shop_id: shopId }),
      });
    }
  }

  console.log(`Receipt ${receipt.id} processed. needs_review=${needsReview}`);
}

// Health check endpoint
serve(async (req) => {
  if (req.method === "GET" && new URL(req.url).pathname.endsWith("health")) {
    return new Response(JSON.stringify({ status: "ok", timestamp: Date.now() }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "";

    // Pick up first 5 pending receipts
    const resp = await fetch(
      `${supabaseUrl}/rest/v1/receipts?select=id,helper_id,employer_id,relation_id,ocr_raw_text,ocr_reconstructed,amount&parse_status=eq.pending&limit=5`,
      { headers: { "apikey": supabaseKey, "Authorization": `Bearer ${supabaseKey}` } }
    );

    const pending: ReceiptRow[] = await resp.json();

    if (pending.length === 0) {
      return new Response(JSON.stringify({ processed: 0, message: "No pending receipts" }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    let processed = 0;
    for (const receipt of pending) {
      try {
        await processReceipt(receipt, supabaseUrl, supabaseKey);
        processed++;
      } catch (e) {
        console.error(`Error processing receipt ${receipt.id}:`, e);
      }
    }

    return new Response(JSON.stringify({ processed }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (error) {
    console.error("receipt-processor error:", error);
    return new Response(JSON.stringify({ error: error.message ?? "Internal error" }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});
