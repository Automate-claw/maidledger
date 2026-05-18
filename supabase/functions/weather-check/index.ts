import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "";

    const hkoUrl = "https://data.weather.gov.hk/weatherAPI/opendata/opendata.php?dataType=warnsum&lang=tc";

    let activeSignal: string | null = null;
    try {
      const hkoRes = await fetch(hkoUrl);
      if (hkoRes.ok) {
        const hkoData = await hkoRes.json();
        const warnings = hkoData.WARN_SUMMARY?.warning || [];
        for (const w of warnings) {
          const code = w.code as string;
          if (['WCLI', 'WCRS', 'WTMW', 'WTSM'].includes(code)) {
            activeSignal = code;
            break;
          }
        }
      }
    } catch (_) {
    }

    if (activeSignal) {
      const signalNames: Record<string, string> = {
        'WCLI': '黃色暴雨',
        'WCRS': '紅色暴雨',
        'WTMW': '八號烈風或暴風信號',
        'WTSM': '十號颶風信號',
      };

      await fetch(
        `${supabaseUrl}/rest/v1/price_alert_suppression`,
        {
          method: "POST",
          headers: {
            "apikey": supabaseKey,
            "Authorization": `Bearer ${supabaseKey}`,
            "Content-Type": "application/json",
            "Prefer": "return=minimal",
          },
          body: JSON.stringify({
            start_time: new Date().toISOString(),
            end_time: new Date(Date.now() + 48 * 60 * 60 * 1000).toISOString(),
            reason: signalNames[activeSignal] || '惡劣天氣',
            suppressed_categories: ['fish', 'vegetables'],
          }),
        },
      );
    }

    return new Response(
      JSON.stringify({ signal_checked: true, active_signal: activeSignal }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    console.error("weather-check error:", error);
    return new Response(JSON.stringify({ error: String(error) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});