// Warm function for keeping edge function containers warm
// Cron: every 2 minutes → ping all edge functions to prevent cold starts

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Edge functions to keep warm
const FUNCTIONS_TO_WARM = [
  "chat-parser",
  "receipt-parser",
];

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Simple GET returns warm status
  if (req.method === "GET") {
    return new Response(
      JSON.stringify({
        status: "warm",
        warmed_functions: FUNCTIONS_TO_WARM,
        timestamp: Date.now(),
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  // POST: Actually ping each function
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

    const results: Record<string, { ok: boolean; latencyMs: number; error?: string }> = {};

    await Promise.all(
      FUNCTIONS_TO_WARM.map(async (func) => {
        const start = Date.now();
        try {
          const resp = await fetch(`${supabaseUrl}/functions/v1/${func}/health`, {
            method: "GET",
            headers: {
              "apikey": anonKey,
              "Authorization": `Bearer ${anonKey}`,
            },
          });
          results[func] = {
            ok: resp.ok,
            latencyMs: Date.now() - start,
          };
        } catch (e) {
          results[func] = {
            ok: false,
            latencyMs: Date.now() - start,
            error: String(e),
          };
        }
      })
    );

    return new Response(
      JSON.stringify({
        status: "warm",
        results,
        timestamp: Date.now(),
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ status: "error", message: String(e) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});