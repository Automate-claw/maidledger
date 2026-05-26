import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface DailySummaryResult {
  success: boolean
  text: string
  error?: string
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing authorization' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } }
    )

    // Get current user
    const { data: { user }, error: userError } = await supabase.auth.getUser()
    if (userError || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const now = new Date()
    
    // Calculate time window: 06:00 today to 06:00 tomorrow
    // If current time is before 06:00, the window started yesterday
    const today6AM = new Date(now)
    today6AM.setHours(6, 0, 0, 0)
    
    let windowStart: Date
    let windowEnd: Date
    
    if (now.getHours() < 6) {
      // Before 6 AM → window started yesterday 6 AM
      windowStart = new Date(today6AM)
      windowStart.setDate(windowStart.getDate() - 1)
      windowEnd = today6AM
    } else {
      // After 6 AM → window started today 6 AM, ends tomorrow 6 AM
      windowStart = today6AM
      windowEnd = new Date(today6AM)
      windowEnd.setDate(windowEnd.getDate() + 1)
    }

    // Query receipts for this employer in the time window
    const { data: receipts, error: receiptsError } = await supabase
      .from('receipts')
      .select(`
        id,
        store_name,
        store_cate,
        amount,
        transaction_date,
        helper_id
      `)
      .eq('employer_id', user.id)
      .gte('created_at', windowStart.toISOString())
      .lt('created_at', windowEnd.toISOString())
      .order('created_at', { ascending: true })

    if (receiptsError) {
      throw receiptsError
    }

    if (!receipts || receipts.length === 0) {
      const dateStr = _formatDate(windowStart)
      const text = `📋 每日採購摘要\n🗓️ ${dateStr}\n\n暫時沒有收據記錄`
      return new Response(JSON.stringify({ success: true, text }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Get receipt IDs
    const receiptIds = receipts.map(r => r.id)

    // Query all receipt items for these receipts
    const { data: items, error: itemsError } = await supabase
      .from('receipt_items')
      .select(`
        id,
        receipt_id,
        item_name,
        extracted_name,
        unit_price,
        extracted_spec
      `)
      .in('receipt_id', receiptIds)
      .order('receipt_id', { ascending: true })

    if (itemsError) {
      throw itemsError
    }

    // Group items by receipt (for shop grouping)
    const itemsByReceipt = new Map<string, typeof items>()
    for (const item of items || []) {
      if (!itemsByReceipt.has(item.receipt_id)) {
        itemsByReceipt.set(item.receipt_id, [])
      }
      itemsByReceipt.get(item.receipt_id)!.push(item)
    }

    // Build formatted text
    const dateStr = _formatDate(windowStart)
    let text = `📋 每日採購摘要\n🗓️ ${dateStr}\n\n`

    let totalAmount = 0

    for (const receipt of receipts) {
      const shopName = receipt.store_name || '未知商戶'
      const shopCate = receipt.store_cate || 'other'
      const shopIcon = _getShopIcon(shopCate)
      const receiptItems = itemsByReceipt.get(receipt.id) || []
      
      text += `${shopIcon} ${shopName}\n`
      
      for (const item of receiptItems) {
        const name = item.extracted_name || item.item_name || '未知項目'
        const spec = item.extracted_spec ? ` ${item.extracted_spec}` : ''
        const price = item.unit_price ? (item.unit_price as number) : 0
        text += `• ${name}${spec} — $${price.toFixed(0)}\n`
        totalAmount += price
      }
      
      text += `\n`
    }

    text += `💰 今日合計：$${totalAmount.toFixed(0)}`

    const result: DailySummaryResult = {
      success: true,
      text,
    }

    return new Response(JSON.stringify(result), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (error) {
    return new Response(JSON.stringify({ 
      success: false, 
      error: error.message || 'Internal error' 
    }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})

function _formatDate(date: Date): string {
  const year = date.getFullYear()
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')
  return `${year}-${month}-${day}`
}

function _getShopIcon(cate: string): string {
  switch (cate) {
    case 'supermarket': return '🏪'
    case 'wet_market': return '🏬'
    case 'pharmacy': return '💊'
    case 'cafe':
    case 'restaurant': return '☕'
    case 'takeaway': return '🍱'
    default: return '🛒'
  }
}