-- Migration: Fix handle_new_user search_path
-- Problem: trigger function couldn't find generate_short_code()
-- because search_path didn't include 'public' schema

ALTER FUNCTION public.handle_new_user SET search_path TO public;