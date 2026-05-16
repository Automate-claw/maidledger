// Supabase Edge Function: notification-broadcast
// Triggered by DB webhook on receipts INSERT
// Broadcasts to employer's Realtime channel

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface ReceiptPayload {
  type: "INSERT";
  table: string;
  record: {
    id: string;
    employer_id: string;
    helper_id: string;
    relation_id: string;
    store_name: string | null;
    amount: number | null;
    created_at: string;
  };
  old_record: null;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const payload: ReceiptPayload = await req.json();

    // Only process INSERT on receipts table
    if (payload.type !== "INSERT" || payload.table !== "receipts") {
      return new Response(
        JSON.stringify({ message: "Ignored" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const record = payload.record;
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    // Fetch employer name from user_profiles
    const employerProfileRes = await fetch(
      `${supabaseUrl}/rest/v1/user_profiles?id=eq.${record.employer_id}&select=name`,
      {
        headers: {
          "apikey": supabaseServiceKey,
          "Authorization": `Bearer ${supabaseServiceKey}`,
        },
      }
    );
    const employers = await employerProfileRes.json();
    const employerName = employers?.[0]?.name ?? "你的僱主";

    // Fetch helper name
    const helperProfileRes = await fetch(
      `${supabaseUrl}/rest/v1/user_profiles?id=eq.${record.helper_id}&select=name`,
      {
        headers: {
          "apikey": supabaseServiceKey,
          "Authorization": `Bearer ${supabaseServiceKey}`,
        },
      }
    );
    const helpers = await helperProfileRes.json();
    const helperName = helpers?.[0]?.name ?? "工人";

    // Build notification payload
    const notification = {
      id: record.id,
      type: "new_receipt",
      title: "📸 收到新收據",
      body: `${helperName} 上傳了收據${record.store_name ? `（${record.store_name}）` : ""} ${record.amount ? " $" + record.amount.toFixed(2) : ""}`,
      employer_id: record.employer_id,
      helper_id: record.helper_id,
      store_name: record.store_name,
      amount: record.amount,
      created_at: record.created_at,
    };

    // Broadcast via Supabase Realtime HTTP API
    const channelName = `notifications:${record.employer_id}`;
    const realtimeRes = await fetch(
      `${supabaseUrl}/realtime/v1/channel/${channelName}`,
      {
        method: "POST",
        headers: {
          "apikey": supabaseServiceKey,
          "Authorization": `Bearer ${supabaseServiceKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          event: "broadcast",
          data: notification,
        }),
      }
    );

    if (!realtimeRes.ok) {
      console.error("Realtime broadcast failed:", await realtimeRes.text());
      return new Response(
        JSON.stringify({ error: "Broadcast failed" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({ success: true, notification }),
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