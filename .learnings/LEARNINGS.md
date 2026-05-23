# LEARNINGS.md

## 2026-05-23 | Supabase Edge Function + Service Role Key Issue

### What happened
- `receipt-processor` edge function runs with `OPENROUTER_API_KEY` and `SUPABASE_*` env vars
- Service role key returned by API (`47b853...`) is NOT a JWT — it's a separate secret
- When used as `Authorization: Bearer <service_role_key>`, PostgREST rejects it as "Invalid API key"
- Supabase Edge Functions use JWT verification (via `auth.jwt()`) — not raw service role key
- The service role key in `.env` / secrets is the raw key for the `supabase` CLI, NOT for edge functions

### How to properly call Supabase from edge functions
- Edge functions resolve `Deno.env.get("SUPABASE_ANON_KEY")` and `Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")` from secrets
- These must be JWT tokens (like anon key), not raw service role strings
- The `service_role` key stored in secrets is for PostgREST direct API calls from trusted environments
- Edge functions use the same JWT-based auth as clients

### Root cause of receipt-processor failures
- `createMasterProduct()` returns `{error:"Invalid API key"}` because the service role key is not a JWT
- This causes the entire product matching chain to fail silently (caught by try/catch)
- The function never creates master_products or price_history

### Fix approach
1. Either: Use a JWT for service role in edge function env (not currently how Supabase CLI works)
2. Or: Use the anon key with RLS bypass for writes (service role bypasses RLS on the connection, but PostgREST still requires JWT)
3. Or: Create a custom JWT service role key specifically for edge functions

### Note
- The current Supabase project has the anon key rotated on 2026-05-22 but the older key still in .env works for some operations
- The secret key rotation happened but the old anon key still works for function invocation (HTTP 200)