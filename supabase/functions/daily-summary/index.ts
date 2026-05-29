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

    // Get current user (helper)
    const { data: { user }, error: userError } = await supabase.auth.getUser()
    if (userError || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const now = new Date()
    
    // Get current date in HK timezone (UTC+8)
    // Since transaction_date has no time component, we just show today's receipts
    const HK_OFFSET = 8 * 60 * 60 * 1000; // 8 hours in ms
    const nowHK = new Date(now.getTime() + HK_OFFSET);
    const todayDateStr = nowHK.toISOString().split('T')[0]; // YYYY-MM-DD in HK
    
    // If before 6 AM HK, show yesterday's data instead
    const currentHourHK = nowHK.getHours();
    let windowStartStr: string;
    let windowEndStr: string;
    
    if (currentHourHK < 6) {
      const yesterday = new Date(nowHK);
      yesterday.setDate(yesterday.getDate() - 1);
      windowStartStr = yesterday.toISOString().split('T')[0];
      windowEndStr = todayDateStr;
    } else {
      windowStartStr = todayDateStr;
      const tomorrow = new Date(nowHK);
      tomorrow.setDate(tomorrow.getDate() + 1);
      windowEndStr = tomorrow.toISOString().split('T')[0];
    }

    // Query receipts for this helper (helper_id = user.id) in the time window
    const { data: receipts, error: receiptsError } = await supabase
      .from('receipts')
      .select(`
        id,
        store_name,
        store_cate,
        amount,
        transaction_date,
        employer_id
      `)
      .eq('helper_id', user.id)
      .gte('transaction_date', windowStartStr)
      .lt('transaction_date', windowEndStr)
      .order('created_at', { ascending: true })

    if (receiptsError) {
      throw receiptsError
    }

    // DEBUG
    console.log('windowStartStr:', windowStartStr, 'windowEndStr:', windowEndStr, 'receipts:', receipts?.length);

    // Get employer's name for the header (if linked)
    let employerDisplay = ''
    if (receipts && receipts.length > 0 && receipts[0].employer_id) {
      const { data: employerProfile } = await supabase
        .from('user_profiles')
        .select('name')
        .eq('id', receipts[0].employer_id)
        .maybeSingle()
      if (employerProfile?.name) {
        employerDisplay = `👤 僱主：${employerProfile.name}\n`
      }
    }

    if (!receipts || receipts.length === 0) {
      const dateStr = windowStartStr
      const text = `📋 每日採購摘要\n🗓️ ${dateStr}\n\n今日暫時沒有收據記錄`
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
    const dateStr = windowStartStr
    let text = `📋 每日採購摘要\n🗓️ ${dateStr}\n`
    if (employerDisplay) text += employerDisplay + '\n'

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