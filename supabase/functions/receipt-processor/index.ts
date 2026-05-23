// ══════════════════════════════════════════════════════════════════════════════
// receipt-processor — event-driven + fallback cron
// ══════════════════════════════════════════════════════════════════════════════
// Dual trigger modes:
//   1. Webhook (DB trigger) → single receipt_id → immediate parse
//   2. Fallback cron (every 5 min) → batch pending → handles webhook failures
//
// Idempotent: only processes receipts still in `pending` status.
// Webhook uses atomic UPDATE WHERE parse_status=pending as mutex.
// Fallback adds 2-minute age filter to avoid colliding with in-flight webhooks.

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
  ocr_raw_text?: string | null;
  ocr_reconstructed?: string | null;
  raw_text?: string | null;
  amount?: string | null;
  transaction_date?: string | null;
}

// In-memory cache
let categoriesCache: {
  storeCategories: { code: string; name: string }[];
  prdCategories: { code: string; name: string }[];
  fetchedAt: number;
} | null = null;
const CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes

const HIGH_AMOUNT_THRESHOLD = 500; // HKD
const FALLBACK_MIN_AGE_SEC = 120; // 2 minutes — skip receipts still being handled by webhook

async function getCategories(supabaseUrl: string, supabaseKey: string) {
  if (categoriesCache) {
    const now = Date.now();
    if (now - categoriesCache.fetchedAt < CACHE_TTL_MS) return categoriesCache;
  }
  const storeFetch = await fetch(`${supabaseUrl}/rest/v1/store_categories?select=code,name_tc&order=display_order.asc`, {
    headers: { "apikey": supabaseKey, Authorization: `Bearer ${supabaseKey}` },
  });
  const prdFetch = await fetch(`${supabaseUrl}/rest/v1/prd_categories?select=code,name_tc&order=display_order.asc`, {
    headers: { "apikey": supabaseKey, Authorization: `Bearer ${supabaseKey}` },
  });
  const storeCategories = await storeFetch.json();
  const prdCategories = await prdFetch.json();
  categoriesCache = { storeCategories, prdCategories, fetchedAt: Date.now() };
  return categoriesCache;
}

function parseJsonResponse(text: string): any {
  const jsonMatch = text.match(/\{[\s\S]*\}/);
  if (!jsonMatch) throw new Error("No JSON found in response");
  return JSON.parse(jsonMatch[0]);
}

function escapeIlike(str: string): string {
  return str.replace(/[%_\\]/g, "\\$&");
}

// ─────────────────────────────────────────────────────────────────────────────
// Product matching helpers
// ─────────────────────────────────────────────────────────────────────────────

async function matchProduct(supabaseUrl: string, supabaseKey: string, itemName: string, prdCate: string | null): Promise<string | null> {
  const aliasResp = await fetch(
    `${supabaseUrl}/rest/v1/product_aliases?select=master_product_id&raw_name=eq.${encodeURIComponent(itemName)}&limit=1`,
    { headers: { "apikey": supabaseKey, Authorization: `Bearer ${supabaseKey}` } }
  );
  const aliases = await aliasResp.json();
  if (aliases?.length > 0) return aliases[0].master_product_id;

  const keywords = itemName.trim().split(/[\s　]+/).filter((k) => k.length > 1).slice(0, 3);
  if (keywords.length === 0) return null;

  const orParts = keywords.map((kw) => `canonical_name.ilike.%${escapeIlike(kw)}%`).join(",");
  const catFilter = prdCate && prdCate !== "other" ? `&prd_cate=eq.${prdCate}` : "";

  const mpResp = await fetch(
    `${supabaseUrl}/rest/v1/master_products?select=id&or=(${orParts})${catFilter}&limit=5`,
    { headers: { "apikey": supabaseKey, Authorization: `Bearer ${supabaseKey}` } }
  );
  const products = await mpResp.json();
  if (products?.length > 0) {
    await fetch(`${supabaseUrl}/rest/v1/product_aliases`, {
      method: "POST",
      headers: { "apikey": supabaseKey, Authorization: `Bearer ${supabaseKey}`, "Content-Type": "application/json", Prefer: "resolution=ignore-duplicates" },
      body: JSON.stringify({ raw_name: itemName, master_product_id: products[0].id, source: "ocr" }),
    });
    return products[0].id;
  }
  return null;
}

async function createMasterProduct(supabaseUrl: string, supabaseKey: string, name: string, prdCate: string): Promise<string> {
  const mpResp = await fetch(`${supabaseUrl}/rest/v1/master_products`, {
    method: "POST",
    headers: { "apikey": supabaseKey, Authorization: `Bearer ${supabaseKey}`, "Content-Type": "application/json", Prefer: "return=representation" },
    body: JSON.stringify({ canonical_name: name.trim(), prd_cate: prdCate || "other", default_unit: "件" }),
  });
  const mp = await mpResp.json();
  const mpId = mp[0]?.id ?? mp?.id;
  if (!mpId) throw new Error("Failed to create master product");

  await fetch(`${supabaseUrl}/rest/v1/product_aliases`, {
    method: "POST",
    headers: { "apikey": supabaseKey, Authorization: `Bearer ${supabaseKey}`, "Content-Type": "application/json", Prefer: "resolution=ignore-duplicates" },
    body: JSON.stringify({ raw_name: name.trim(), master_product_id: mpId, source: "ocr" }),
  });
  return mpId;
}

// ─────────────────────────────────────────────────────────────────────────────
// Shop matching helpers
// ─────────────────────────────────────────────────────────────────────────────

async function matchShop(supabaseUrl: string, supabaseKey: string, rawShopName: string): Promise<string | null> {
  const aliasResp = await fetch(
    `${supabaseUrl}/rest/v1/shops?select=id&shop_aliases(raw_name.ilike.%${escapeIlike(rawShopName)}%)&limit=1`,
    { headers: { "apikey": supabaseKey, Authorization: `Bearer ${supabaseKey}` } }
  );
  const shops = await aliasResp.json();
  if (shops?.length > 0) return shops[0].id;

  const nameResp = await fetch(
    `${supabaseUrl}/rest/v1/shops?select=id&canonical_name.ilike.%${escapeIlike(rawShopName)}%&limit=1`,
    { headers: { "apikey": supabaseKey, Authorization: `Bearer ${supabaseKey}` } }
  );
  const shops2 = await nameResp.json();
  if (shops2?.length > 0) return shops2[0].id;

  return null;
}

async function createShop(supabaseUrl: string, supabaseKey: string, rawShopName: string, shopType: string | null, location: string | null): Promise<string> {
  const shopTypeMap: Record<string, string> = {
    supermarket: "supermarket", wet_market: "wet_market",
    convenience: "convenience", online: "online", restaurant: "restaurant", other: "other",
  };
  const mappedType = shopType && shopTypeMap[shopType] ? shopTypeMap[shopType] : "other";

  const shopResp = await fetch(`${supabaseUrl}/rest/v1/shops`, {
    method: "POST",
    headers: { "apikey": supabaseKey, Authorization: `Bearer ${supabaseKey}`, "Content-Type": "application/json", Prefer: "return=representation" },
    body: JSON.stringify({ canonical_name: rawShopName.trim(), shop_type: mappedType, region: location ?? null }),
  });
  const shopJson = await shopResp.json();
  const shopId = shopJson[0]?.id ?? shopJson?.id;
  if (!shopId) throw new Error("Failed to create shop");

  await fetch(`${supabaseUrl}/rest/v1/shop_aliases`, {
    method: "POST",
    headers: { "apikey": supabaseKey, Authorization: `Bearer ${supabaseKey}`, "Content-Type": "application/json", Prefer: "resolution=ignore-duplicates" },
    body: JSON.stringify({ raw_name: rawShopName.trim(), shop_id: shopId, source: "ocr" }),
  });
  return shopId;
}

// ─────────────────────────────────────────────────────────────────────────────
// LLM Parse
// ─────────────────────────────────────────────────────────────────────────────

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

  if (!textResponse) throw new Error(`LLM failed for all models. Last error: ${lastError}`);
  return parseJsonResponse(textResponse);
}

// ─────────────────────────────────────────────────────────────────────────────
// Atomic lock + process (shared by webhook and cron modes)
// Returns true if processed, false if skipped (already taken / not pending)
// ─────────────────────────────────────────────────────────────────────────────

async function tryProcessReceipt(receiptId: string, supabaseUrl: string, supabaseKey: string): Promise<boolean> {
  // ── Atomic mutex: only update if still in `pending` state ──
  // This is the key to preventing race conditions when multiple webhooks fire at once
  const lockResp = await fetch(
    `${supabaseUrl}/rest/v1/receipts?id=eq.${receiptId}&parse_status=eq.pending&select=id,ocr_raw_text,ocr_reconstructed,raw_text,amount`,
    {
      method: "PATCH",
      headers: { "apikey": supabaseKey, Authorization: `Bearer ${supabaseKey}`, "Content-Type": "application/json", Prefer: "return=representation" },
      body: JSON.stringify({ parse_status: "processing" }),
    }
  );

  if (!lockResp.ok) {
    console.error(`Lock failed for ${receiptId}: ${lockResp.status}`);
    return false;
  }

  const locked: ReceiptRow[] = await lockResp.json();
  if (!locked || locked.length === 0) {
    // Receipt already processed, or not in pending state — skip
    console.log(`Receipt ${receiptId} skipped (not pending or already locked)`);
    return false;
  }

  const receipt = locked[0];
  console.log(`Processing receipt ${receiptId}...`);

  let parseResult: any;
  try {
    parseResult = await callLLMParse(
      (receipt.ocr_raw_text || receipt.raw_text || "").trim(),
      (receipt.ocr_reconstructed || "").trim(),
      supabaseUrl,
      supabaseKey
    );
  } catch (e) {
    // LLM failed → mark failed, leave for fallback cron retry
    await fetch(`${supabaseUrl}/rest/v1/receipts?id=eq.${receiptId}`, {
      method: "PATCH",
      headers: { "apikey": supabaseKey, Authorization: `Bearer ${supabaseKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ parse_status: "failed" }),
    });
    console.error(`Receipt ${receiptId} LLM failed:`, e);
    return true; // did attempt (even though failed)
  }

  // Determine needs_review
  const confidence = parseResult.parse_confidence ?? 0;
  const amount = parseResult.total_amount ?? 0;
  const needsReview = confidence < 0.7 || amount > HIGH_AMOUNT_THRESHOLD;

  const cats = await getCategories(supabaseUrl, supabaseKey);
  const validStoreCodes = cats.storeCategories.map((c) => c.code);
  const validPrdCodes = cats.prdCategories.map((c) => c.code);

  // Update receipt with parsed data
  await fetch(`${supabaseUrl}/rest/v1/receipts?id=eq.${receiptId}`, {
    method: "PATCH",
    headers: { "apikey": supabaseKey, Authorization: `Bearer ${supabaseKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      store_name: parseResult.store_name ?? "未知商戶",
      store_cate: validStoreCodes.includes(parseResult.store_cate) ? parseResult.store_cate : "other",
      location: parseResult.location ?? null,
      amount: parseResult.total_amount ?? null,
      transaction_date: parseResult.transaction_date ?? null,
      parsed_data: JSON.stringify(parseResult),
      parse_confidence: confidence,
      needs_review: needsReview,
      parse_status: "parsed",
    }),
  });

  // Insert receipt_items
  const items: any[] = parseResult.items ?? [];
  if (items.length > 0) {
    const itemRows = items.map((item) => ({
      receipt_id: receiptId,
      item_name: item.item_name ?? "",
      item_raw_text: item.item_raw_text ?? "",
      qty: item.qty ?? 1,
      unit_price: item.unit_price ?? null,
      line_total: item.unit_price != null && item.qty != null ? item.unit_price * item.qty : null,
      prd_cate: validPrdCodes.includes(item.prd_cate) ? item.prd_cate : "other",
    }));

    await fetch(`${supabaseUrl}/rest/v1/receipt_items`, {
      method: "POST",
      headers: { "apikey": supabaseKey, Authorization: `Bearer ${supabaseKey}`, "Content-Type": "application/json", Prefer: "return=representation" },
      body: JSON.stringify(itemRows),
    });

    // Product matching + price_history
    for (const item of items) {
      try {
        let masterProductId = await matchProduct(supabaseUrl, supabaseKey, item.item_name, item.prd_cate);
        if (!masterProductId) {
          masterProductId = await createMasterProduct(supabaseUrl, supabaseKey, item.item_name, item.prd_cate || "other");
        }

        // Bind to receipt_item — use id DESC to get latest inserted row
        const itemResp = await fetch(
          `${supabaseUrl}/rest/v1/receipt_items?select=id,master_product_id&receipt_id=eq.${receiptId}&item_name=eq.${encodeURIComponent(item.item_name)}&order=id.desc&limit=1`,
          { headers: { "apikey": supabaseKey, Authorization: `Bearer ${supabaseKey}` } }
        );
        const itemRows2 = await itemResp.json();
        const targetItem = itemRows2 && itemRows2.length > 0 ? itemRows2[0] : null;

        if (!targetItem) continue;

        const targetMpId = masterProductId ?? targetItem.master_product_id;
        if (!targetMpId) continue;

        if (!targetItem.master_product_id || targetItem.master_product_id !== targetMpId) {
          await fetch(`${supabaseUrl}/rest/v1/receipt_items?id=eq.${targetItem.id}`, {
            method: "PATCH",
            headers: { "apikey": supabaseKey, Authorization: `Bearer ${supabaseKey}`, "Content-Type": "application/json" },
            body: JSON.stringify({ master_product_id: targetMpId }),
          });
        }

        if (item.unit_price != null) {
          await fetch(`${supabaseUrl}/rest/v1/price_history`, {
            method: "POST",
            headers: { "apikey": supabaseKey, Authorization: `Bearer ${supabaseKey}`, "Content-Type": "application/json" },
            body: JSON.stringify({
              master_product_id: targetMpId,
              region: parseResult.location ?? null,
              location: parseResult.location ?? null,
              price: item.unit_price * (item.qty ?? 1),
              original_price: item.unit_price,
              unit: "件",
              source_receipt_id: receiptId,
              recorded_at: parseResult.transaction_date ?? new Date().toISOString().split("T")[0],
            }),
          });
        }
      } catch (e) {
        console.error(`Product matching error for "${item.item_name}":`, e);
      }
    }
  }

  // Shop matching
  if (parseResult.store_name) {
    let shopId = await matchShop(supabaseUrl, supabaseKey, parseResult.store_name);
    if (!shopId) {
      try {
        shopId = await createShop(supabaseUrl, supabaseKey, parseResult.store_name, parseResult.store_cate, parseResult.location);
      } catch (e) {
        console.error(`Failed to create shop "${parseResult.store_name}":`, e);
      }
    }
    if (shopId) {
      await fetch(`${supabaseUrl}/rest/v1/receipts?id=eq.${receiptId}`, {
        method: "PATCH",
        headers: { "apikey": supabaseKey, Authorization: `Bearer ${supabaseKey}`, "Content-Type": "application/json" },
        body: JSON.stringify({ shop_id: shopId }),
      });
    }
  }

  console.log(`Receipt ${receiptId} processed. needs_review=${needsReview}`);
  return true;
}

// ─────────────────────────────────────────────────────────────────────────────
// HTTP handler — supports both webhook (single) and cron (batch) modes
// ─────────────────────────────────────────────────────────────────────────────

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

    // ── WEBHOOK MODE: single receipt_id in body ──
    // POST { "receipt_id": "uuid" }  →  process one immediately
    let body: any = {};
    try {
      body = await req.json();
    } catch { /* empty body for cron GET */ }

    if (body?.receipt_id) {
      const receiptId: string = body.receipt_id;
      const processed = await tryProcessReceipt(receiptId, supabaseUrl, supabaseKey);
      return new Response(
        JSON.stringify({ mode: "webhook", receipt_id: receiptId, processed }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── CRON FALLBACK MODE: batch pending receipts with age filter ──
    // Cron sends GET (no body) — pick up old pending receipts
    const minAgeSec = FALLBACK_MIN_AGE_SEC;
    const resp = await fetch(
      `${supabaseUrl}/rest/v1/receipts?select=id&parse_status=eq.pending&created_at=lt.now()-%20seconds%20${minAgeSec}&limit=5`.replace("%20seconds%20", "%20seconds%20"),
      { headers: { "apikey": supabaseKey, Authorization: `Bearer ${supabaseKey}` } }
    );

    if (!resp.ok) {
      const errText = await resp.text();
      return new Response(JSON.stringify({ error: "DB query failed", details: errText }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const pending: { id: string }[] = await resp.json();

    if (pending.length === 0) {
      return new Response(JSON.stringify({ mode: "cron", processed: 0, message: "No stale pending receipts" }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    let processed = 0;
    for (const row of pending) {
      try {
        const ok = await tryProcessReceipt(row.id, supabaseUrl, supabaseKey);
        if (ok) processed++;
      } catch (e) {
        console.error(`Cron error processing receipt ${row.id}:`, e);
      }
    }

    return new Response(
      JSON.stringify({ mode: "cron", processed, total: pending.length }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    console.error("receipt-processor error:", error);
    return new Response(
      JSON.stringify({ error: error.message ?? "Internal error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" }
    });
  }
});