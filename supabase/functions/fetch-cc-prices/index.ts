// fetch-cc-prices Edge Function - Optimized for speed
// Fetch CC data and bulk upsert to cc_prices table

const CC_JSON_URL = "https://online-price-watch.consumer.org.hk/opw/opendata/pricewatch.json"

interface CCProduct {
  code: string
  brand?: { en?: string; 'zh-Hant'?: string }
  name?: { en?: string; 'zh-Hant'?: string }
  cat1Name?: { en?: string; 'zh-Hant'?: string }
  cat2Name?: { en?: string; 'zh-Hant'?: string }
  cat3Name?: { en?: string; 'zh-Hant'?: string }
  prices?: Array<{ supermarketCode: string; price: string }>
}

function extractWeight(nameStr: string): number | null {
  const patterns: [RegExp, number][] = [
    [/(\d+)\s*g\b/i, 1],
    [/(\d+)\s*公斤/i, 1000],
    [/([\d.]+)\s*斤/i, 604.79],
    [/([\d.]+)\s*兩/i, 37.8],
    [/(\d+)\s*磅/i, 453.6],
    [/(\d+)\s*oz/i, 28.35],
  ]
  for (const [p, m] of patterns) {
    const m2 = nameStr.match(p)
    if (m2) return Math.round(parseFloat(m2[1]) * m * 100) / 100
  }
  return null
}

async function main() {
  const t0 = Date.now()
  
  // Step 1: Fetch CC data
  const resp = await fetch(CC_JSON_URL, { headers: { 'User-Agent': 'Mozilla/5.0' } })
  if (!resp.ok) return Response.json({ error: `Fetch failed: ${resp.status}` }, { status: 500 })
  
  const ccData: CCProduct[] = await resp.json()
  
  // Step 2: Process all products
  const records = ccData.map(p => {
    const name = p.name || {}
    const brand = p.brand || {}
    const cat1 = p.cat1Name || {}
    const cat2 = p.cat2Name || {}
    const cat3 = p.cat3Name || {}
    
    const prices: Record<string, number> = {}
    for (const x of (p.prices || [])) {
      if (x.supermarketCode && x.price) prices[x.supermarketCode] = parseFloat(x.price)
    }
    
    const nameEn = name.en || ''
    const nameZh = name['zh-Hant'] || ''
    const w = extractWeight(`${nameEn} ${nameZh}`)
    
    const pricesStr = JSON.stringify(prices)
    const avgPrice = Object.keys(prices).length ? Object.values(prices).reduce((a, b) => a + b, 0) / Object.keys(prices).length : 0
    const pp100 = (w && avgPrice) ? Math.round((avgPrice / w * 100) * 100) / 100 : null
    
    return {
      cc_code: p.code,
      name_en: nameEn,
      name_zh: nameZh,
      brand_en: brand.en || '',
      brand_zh: brand['zh-Hant'] || '',
      cat1_en: cat1.en || '',
      cat1_zh: cat1['zh-Hant'] || '',
      cat2_en: cat2.en || '',
      cat2_zh: cat2['zh-Hant'] || '',
      cat3_en: cat3.en || '',
      cat3_zh: cat3['zh-Hant'] || '',
      prices: pricesStr,
      standard_weight_g: w,
      price_per_100g: pp100,
      updated_at: new Date().toISOString()
    }
  }).filter(r => r.cc_code)
  
  // Step 3: Bulk upsert via REST API
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  
  const upsertResp = await fetch(`${supabaseUrl}/rest/v1/cc_prices?upsert=true&on_conflict=cc_code`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'apikey': supabaseKey,
      'Authorization': `Bearer ${supabaseKey}`,
      'Prefer': 'resolution=merge-duplicates'
    },
    body: JSON.stringify(records)
  })
  
  const elapsed = (Date.now() - t0) / 1000
  
  if (!upsertResp.ok) {
    const err = await upsertResp.text()
    return Response.json({ error: `Upsert failed: ${err}` }, { status: 500 })
  }
  
  return Response.json({
    status: 'success',
    total: ccData.length,
    upserted: records.length,
    elapsed_sec: elapsed
  })
}

export { main }