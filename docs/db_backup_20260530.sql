


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_net" WITH SCHEMA "public";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."backfill_receipts_on_link"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  -- When a relation becomes active, update all unassigned receipts
  IF NEW.status = 'active' AND TG_OP = 'UPDATE' THEN
    UPDATE receipts
    SET employer_id = NEW.employer_id,
        relation_id = NEW.id
    WHERE helper_id = NEW.helper_id
      AND employer_id IS NULL
      AND relation_id IS NULL;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."backfill_receipts_on_link"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_short_code"() RETURNS character varying
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_code VARCHAR(6);
  v_exists BOOLEAN;
BEGIN
  -- Generate until unique (handles collisions)
  LOOP
    v_code := UPPER(
      SUBSTRING(
        'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' FROM
        floor(random() * 28)::int + 1 FOR 1
      ) ||
      SUBSTRING(
        'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' FROM
        floor(random() * 28)::int + 1 FOR 1
      ) ||
      SUBSTRING(
        'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' FROM
        floor(random() * 28)::int + 1 FOR 1
      ) ||
      SUBSTRING(
        'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' FROM
        floor(random() * 28)::int + 1 FOR 1
      ) ||
      SUBSTRING(
        'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' FROM
        floor(random() * 28)::int + 1 FOR 1
      ) ||
      SUBSTRING(
        'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' FROM
        floor(random() * 28)::int + 1 FOR 1
      )
    );

    SELECT EXISTS(SELECT 1 FROM user_profiles WHERE short_code = v_code) INTO v_exists;
    IF NOT v_exists THEN
      RETURN v_code;
    END IF;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."generate_short_code"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."user_profiles" (
    "id" "uuid" NOT NULL,
    "role" "text" NOT NULL,
    "name" "text" NOT NULL,
    "phone" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "short_code" character(6),
    "household_size" integer,
    "default_location" "text",
    CONSTRAINT "user_profiles_role_check" CHECK (("role" = ANY (ARRAY['employer'::"text", 'helper'::"text"])))
);


ALTER TABLE "public"."user_profiles" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_employer_by_code"("p_code" "text") RETURNS "public"."user_profiles"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  RETURN (
    SELECT up FROM user_profiles up
    WHERE up.id = p_code::UUID
    AND up.role = 'employer'
  );
END;
$$;


ALTER FUNCTION "public"."get_employer_by_code"("p_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_price_alert"("p_category" "text", "p_price" real) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_avg_price REAL;
  v_min_price REAL;
  v_max_price REAL;
  v_supermarket_avg REAL;
  v_difference REAL;
  v_alert_level TEXT;
BEGIN
  -- Get average price for category from last 7 days
  SELECT AVG(price), MIN(price), MAX(price)
  INTO v_avg_price, v_min_price, v_max_price
  FROM price_data
  WHERE category = p_category
    AND scraped_at > NOW() - INTERVAL '7 days';

  -- Get supermarket-specific average
  SELECT AVG(price)
  INTO v_supermarket_avg
  FROM (
    SELECT supermarket, AVG(price) as avg_price
    FROM price_data
    WHERE category = p_category
      AND scraped_at > NOW() - INTERVAL '7 days'
    GROUP BY supermarket
  ) sub;

  -- Calculate difference
  IF v_avg_price IS NOT NULL AND v_avg_price > 0 THEN
    v_difference := ((p_price - v_avg_price) / v_avg_price) * 100;

    -- Determine alert level
    IF v_difference < -10 THEN
      v_alert_level := 'green';  -- Much cheaper than average
    ELSIF v_difference < 5 THEN
      v_alert_level := 'green';  -- Slightly cheaper or normal
    ELSIF v_difference < 20 THEN
      v_alert_level := 'yellow'; -- Slightly expensive
    ELSE
      v_alert_level := 'red';    -- Much more expensive
    END IF;
  ELSE
    v_difference := 0;
    v_alert_level := 'unknown';
  END IF;

  RETURN jsonb_build_object(
    'category', p_category,
    'input_price', p_price,
    'avg_price', ROUND(v_avg_price::numeric, 2),
    'min_price', v_min_price,
    'max_price', v_max_price,
    'difference_percent', ROUND(v_difference::numeric, 1),
    'alert_level', v_alert_level,
    'message', CASE
      WHEN v_difference < -10 THEN '✅ 比超市平好多！'
      WHEN v_difference < 5 THEN '✅ 正常價'
      WHEN v_difference < 20 THEN '⚠️ 偏貴'
      ELSE '🚨 貴過超市好多！'
    END
  );
END;
$$;


ALTER FUNCTION "public"."get_price_alert"("p_category" "text", "p_price" real) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_price_alert"("p_category" "text", "p_price" numeric) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_avg_price DECIMAL;
  v_min_price DECIMAL;
  v_max_price DECIMAL;
  v_difference DECIMAL;
  v_alert_level TEXT;
  v_message TEXT;
BEGIN
  -- Get average price for category from last 7 days
  SELECT AVG(price), MIN(price), MAX(price)
  INTO v_avg_price, v_min_price, v_max_price
  FROM price_data
  WHERE category = p_category
    AND scraped_at > NOW() - INTERVAL '7 days';

  -- Calculate difference
  IF v_avg_price IS NOT NULL AND v_avg_price > 0 THEN
    v_difference := ((p_price - v_avg_price) / v_avg_price) * 100;

    -- Determine alert level
    IF v_difference < -10 THEN
      v_alert_level := 'green';
      v_message := '✅ 比超市平好多！';
    ELSIF v_difference < 5 THEN
      v_alert_level := 'green';
      v_message := '✅ 正常價';
    ELSIF v_difference < 20 THEN
      v_alert_level := 'yellow';
      v_message := '⚠️ 偏貴';
    ELSE
      v_alert_level := 'red';
      v_message := '🚨 貴過超市好多！';
    END IF;
  ELSE
    v_difference := 0;
    v_alert_level := 'unknown';
    v_message := '⚪ 暂无超市價格數據';
  END IF;

  RETURN jsonb_build_object(
    'category', p_category,
    'input_price', p_price,
    'avg_price', ROUND(v_avg_price::numeric, 2),
    'min_price', v_min_price,
    'max_price', v_max_price,
    'difference_percent', ROUND(v_difference::numeric, 1),
    'alert_level', v_alert_level,
    'message', v_message
  );
END;
$$;


ALTER FUNCTION "public"."get_price_alert"("p_category" "text", "p_price" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_receipt"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$

BEGIN
  IF NEW.parse_status = 'pending' THEN
    PERFORM net.http_post(
      url := 'https://hnyazfrkzpxdjiyfzemm.supabase.co/functions/v1/receipt-orchestrate',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
      ),
      body := jsonb_build_object(
        'receipt_id', NEW.id
      )
    );
  END IF;
  RETURN NEW;
END;

$$;


ALTER FUNCTION "public"."handle_new_receipt"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  INSERT INTO public.user_profiles (id, role, name, short_code)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'role', 'helper'),
    COALESCE(
      NEW.raw_user_meta_data->>'name',
      NEW.raw_user_meta_data->>'full_name',
      NEW.email
    ),
    generate_short_code()  -- Add this line
  );
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."employer_helper_relations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "employer_id" "uuid" NOT NULL,
    "helper_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'active'::"text",
    "created_at" timestamp with time zone DEFAULT ("timezone"('Asia/Hong_Kong'::"text", "now"()))::timestamp with time zone,
    "employer_code" character(6),
    CONSTRAINT "employer_helper_relations_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'inactive'::"text", 'pending'::"text"])))
);


ALTER TABLE "public"."employer_helper_relations" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."link_helper_to_employer_via_code"("p_employer_code" "uuid", "p_helper_id" "uuid") RETURNS "public"."employer_helper_relations"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_relation employer_helper_relations%ROWTYPE;
BEGIN
  -- Look for a pending relation with this employer, update to active
  UPDATE employer_helper_relations
  SET status = 'active', helper_id = p_helper_id
  WHERE employer_id = p_employer_code
    AND status = 'pending'
    AND helper_id IS NULL
  RETURNING * INTO v_relation;

  IF v_relation.id IS NULL THEN
    -- No pending relation found, create new active one
    INSERT INTO employer_helper_relations (employer_id, helper_id, status)
    VALUES (p_employer_code, p_helper_id, 'active')
    RETURNING * INTO v_relation;
  END IF;

  RETURN v_relation;
END;
$$;


ALTER FUNCTION "public"."link_helper_to_employer_via_code"("p_employer_code" "uuid", "p_helper_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."parse_receipt_text"("p_raw_text" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_result JSONB;
BEGIN
  -- This would call Gemini Edge Function
  -- For now, return structured placeholder
  v_result := jsonb_build_object(
    'items', ARRAY[]::TEXT[],
    'total', NULL,
    'category', 'food',
    'confidence', 0.5
  );

  RETURN v_result;
END;
$$;


ALTER FUNCTION "public"."parse_receipt_text"("p_raw_text" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_receipt_shop"("p_receipt_id" "uuid", "p_shop_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$ BEGIN UPDATE receipts SET shop_id = p_shop_id WHERE id = p_receipt_id; END; $$;


ALTER FUNCTION "public"."set_receipt_shop"("p_receipt_id" "uuid", "p_shop_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."test_trigger"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$ BEGIN PERFORM 1; END; $$;


ALTER FUNCTION "public"."test_trigger"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_receipt_shop"("p_receipt_id" "uuid", "p_shop_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ BEGIN UPDATE receipts SET shop_id = p_shop_id WHERE id = p_receipt_id; END; $$;


ALTER FUNCTION "public"."update_receipt_shop"("p_receipt_id" "uuid", "p_shop_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_updated_at_column"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."upsert_cc_prices"("records" "jsonb") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  count INTEGER;
BEGIN
  INSERT INTO cc_prices (cc_code, name_en, name_zh, brand_en, brand_zh, cat1_en, cat1_zh, cat2_en, cat2_zh, cat3_en, cat3_zh, prices, standard_weight_g, price_per_100g, updated_at)
  SELECT * FROM jsonb_to_recordset(records)
    AS (cc_code TEXT, name_en TEXT, name_zh TEXT, brand_en TEXT, brand_zh TEXT, cat1_en TEXT, cat1_zh TEXT, cat2_en TEXT, cat2_zh TEXT, cat3_en TEXT, cat3_zh TEXT, prices JSONB, standard_weight_g INTEGER, price_per_100g DECIMAL, updated_at TIMESTAMPTZ)
  ON CONFLICT (cc_code) DO UPDATE SET
    name_en = EXCLUDED.name_en,
    name_zh = EXCLUDED.name_zh,
    brand_en = EXCLUDED.brand_en,
    brand_zh = EXCLUDED.brand_zh,
    cat1_en = EXCLUDED.cat1_en,
    cat1_zh = EXCLUDED.cat1_zh,
    cat2_en = EXCLUDED.cat2_en,
    cat2_zh = EXCLUDED.cat2_zh,
    cat3_en = EXCLUDED.cat3_en,
    cat3_zh = EXCLUDED.cat3_zh,
    prices = EXCLUDED.prices,
    standard_weight_g = EXCLUDED.standard_weight_g,
    price_per_100g = EXCLUDED.price_per_100g,
    updated_at = EXCLUDED.updated_at;
  
  GET DIAGNOSTICS count = ROW_COUNT;
  RETURN count;
END;
$$;


ALTER FUNCTION "public"."upsert_cc_prices"("records" "jsonb") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."app_errors" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "error_type" "text" NOT NULL,
    "source" "text" NOT NULL,
    "message" "text",
    "extra_data" "jsonb",
    "resolved" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."app_errors" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cc_prices" (
    "cc_code" "text" NOT NULL,
    "name_en" "text",
    "name_zh" "text",
    "brand_en" "text",
    "brand_zh" "text",
    "cat1_en" "text",
    "cat1_zh" "text",
    "cat2_en" "text",
    "cat2_zh" "text",
    "cat3_en" "text",
    "cat3_zh" "text",
    "prices" "jsonb",
    "standard_weight_g" integer,
    "price_per_100g" numeric,
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."cc_prices" OWNER TO "postgres";


COMMENT ON TABLE "public"."cc_prices" IS 'Consumer Council price data - supermarket reference prices';



COMMENT ON COLUMN "public"."cc_prices"."cc_code" IS 'Consumer Council product code, e.g. P000003343';



COMMENT ON COLUMN "public"."cc_prices"."standard_weight_g" IS 'Standard package weight in grams, extracted from product name';



COMMENT ON COLUMN "public"."cc_prices"."price_per_100g" IS 'Normalized price per 100g for cross-product comparison';



CREATE TABLE IF NOT EXISTS "public"."chat_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"(),
    "user_id" "text",
    "input_text" "text",
    "output_response" "jsonb",
    "is_expense" boolean,
    "completeness" "text",
    "total_amount" numeric,
    "parse_confidence" numeric,
    "llm_model_used" "text",
    "llm_raw_response" "text",
    "duration_ms" integer,
    "error" "text",
    "created_at" timestamp with time zone DEFAULT ("timezone"('Asia/Hong_Kong'::"text", "now"()))::timestamp with time zone
);


ALTER TABLE "public"."chat_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."chat_rate_limits" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "text" NOT NULL,
    "is_expense" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."chat_rate_limits" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."employer_payments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "relation_id" "uuid",
    "employer_id" "uuid",
    "helper_id" "uuid" NOT NULL,
    "amount" numeric(10,2) NOT NULL,
    "payment_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "note" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "created_by" "uuid"
);


ALTER TABLE "public"."employer_payments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."expense_summaries" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "employer_id" "uuid" NOT NULL,
    "helper_id" "uuid",
    "relation_id" "uuid",
    "month" "date" NOT NULL,
    "category" "text",
    "total_amount" numeric(10,2) DEFAULT 0,
    "transaction_count" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."expense_summaries" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."master_products" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "canonical_name" "text" NOT NULL,
    "brand" "text",
    "prd_cate" "text",
    "default_unit" "text",
    "search_keywords" "text"[],
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."master_products" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."prd_categories" (
    "id" integer NOT NULL,
    "code" "text" NOT NULL,
    "name_tc" "text" NOT NULL,
    "name_en" "text",
    "description" "text",
    "display_order" integer DEFAULT 0
);


ALTER TABLE "public"."prd_categories" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."prd_categories_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."prd_categories_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."prd_categories_id_seq" OWNED BY "public"."prd_categories"."id";



CREATE TABLE IF NOT EXISTS "public"."price_alert_suppression" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "start_time" timestamp with time zone NOT NULL,
    "end_time" timestamp with time zone NOT NULL,
    "reason" "text",
    "suppressed_categories" "text"[],
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."price_alert_suppression" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."price_alerts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "receipt_id" "uuid",
    "category" "text" NOT NULL,
    "input_price" numeric(10,2) NOT NULL,
    "avg_price" numeric(10,2),
    "min_price" numeric(10,2),
    "max_price" numeric(10,2),
    "difference_percent" numeric(5,1),
    "alert_level" "text",
    "message" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "comparison_type" "text" DEFAULT 'last_purchase'::"text",
    "price_before" numeric(10,2),
    "weather_suppressed" boolean DEFAULT false,
    "region" "text",
    CONSTRAINT "price_alerts_alert_level_check" CHECK (("alert_level" = ANY (ARRAY['green'::"text", 'yellow'::"text", 'red'::"text", 'unknown'::"text"])))
);


ALTER TABLE "public"."price_alerts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."price_data" (
    "id" integer NOT NULL,
    "supermarket" "text" NOT NULL,
    "category" "text" NOT NULL,
    "product_name" "text" NOT NULL,
    "price" numeric(10,2) NOT NULL,
    "unit" "text" DEFAULT 'unit'::"text",
    "source_url" "text",
    "scraped_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "price_data_category_check" CHECK (("category" = ANY (ARRAY['fish'::"text", 'pork'::"text", 'beef'::"text", 'chicken'::"text", 'vegetables'::"text", 'others'::"text"]))),
    CONSTRAINT "price_data_supermarket_check" CHECK (("supermarket" = ANY (ARRAY['hktvmall'::"text", 'wellcome'::"text", 'parknshop'::"text"])))
);


ALTER TABLE "public"."price_data" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."price_data_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."price_data_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."price_data_id_seq" OWNED BY "public"."price_data"."id";



CREATE TABLE IF NOT EXISTS "public"."price_history" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "master_product_id" "uuid",
    "shop_id" "uuid",
    "location" "text",
    "region" "text",
    "price" numeric(10,2) NOT NULL,
    "unit" "text",
    "source_receipt_id" "uuid",
    "recorded_at" "date" DEFAULT CURRENT_DATE,
    "created_at" timestamp with time zone DEFAULT ("timezone"('Asia/Hong_Kong'::"text", "now"()))::timestamp with time zone,
    "original_price" numeric(10,2),
    "total_paid" numeric(10,2),
    "is_discount_bundle" boolean DEFAULT false
);


ALTER TABLE "public"."price_history" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."product_aliases" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "raw_name" "text" NOT NULL,
    "master_product_id" "uuid",
    "source" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "product_aliases_source_check" CHECK (("source" = ANY (ARRAY['ocr'::"text", 'crawler'::"text", 'manual'::"text", 'seed'::"text"])))
);


ALTER TABLE "public"."product_aliases" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."receipt_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "receipt_id" "uuid" NOT NULL,
    "item_name" "text" NOT NULL,
    "item_raw_text" "text",
    "qty" numeric(10,3) DEFAULT 1,
    "unit_price" numeric(10,2),
    "prd_cate" "text",
    "line_total" numeric(10,2),
    "created_at" timestamp with time zone DEFAULT ("timezone"('Asia/Hong_Kong'::"text", "now"()))::timestamp with time zone,
    "master_product_id" "uuid",
    "actual_price" numeric(10,2),
    "is_discounted" boolean DEFAULT false,
    "discount_note" "text",
    "extracted_brand" "text",
    "extracted_name" "text",
    "extracted_spec" "text",
    "weight_grams" numeric,
    "price_per_gram" numeric,
    "cc_code" "text",
    "cc_price_per_gram" numeric,
    "subcategory_code" "text"
);


ALTER TABLE "public"."receipt_items" OWNER TO "postgres";


COMMENT ON COLUMN "public"."receipt_items"."item_name" IS 'LLM 原始輸出（含品牌/容量/店鋪特異字眼），兼容性保留；建議使用 extracted_name 做匹配';



COMMENT ON COLUMN "public"."receipt_items"."extracted_brand" IS '標準化品牌名稱（如：759阿信屋 / 維記 / 雀巢），從 LLM 結構化解析取得';



COMMENT ON COLUMN "public"."receipt_items"."extracted_name" IS '純產品核心名稱，不含品牌、容量、店鋪特異字眼（如：鮮牛奶 / 濕紙巾 / 聖擊袋）';



COMMENT ON COLUMN "public"."receipt_items"."extracted_spec" IS '規格或容量（如：946ml / 10卷裝 / 大號），無則 null';



CREATE TABLE IF NOT EXISTS "public"."receipts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "employer_id" "uuid",
    "helper_id" "uuid",
    "relation_id" "uuid",
    "raw_text" "text" NOT NULL,
    "parsed_data" "jsonb",
    "amount" numeric(10,2),
    "items" "jsonb" DEFAULT '[]'::"jsonb",
    "sync_status" "text" DEFAULT 'pending'::"text",
    "local_timestamp" bigint NOT NULL,
    "server_timestamp" bigint DEFAULT ((EXTRACT(epoch FROM "timezone"('Asia/Hong_Kong'::"text", "now"())))::bigint * 1000),
    "image_local_path" "text",
    "created_at" timestamp with time zone DEFAULT ("timezone"('Asia/Hong_Kong'::"text", "now"()))::timestamp with time zone,
    "updated_at" timestamp with time zone DEFAULT ("timezone"('Asia/Hong_Kong'::"text", "now"()))::timestamp with time zone,
    "store_name" "text",
    "store_cate" "text",
    "location" "text",
    "transaction_date" "date",
    "shop_id" "uuid",
    "ocr_raw_text" "text",
    "ocr_reconstructed" "text",
    "parse_status" "text" DEFAULT 'pending'::"text",
    "parse_confidence" real,
    "needs_review" boolean DEFAULT false,
    "reviewed_by" "uuid",
    "reviewed_at" timestamp with time zone,
    "date_anomaly" boolean DEFAULT false NOT NULL,
    "created_by" "uuid",
    CONSTRAINT "receipts_parse_status_check" CHECK (("parse_status" = ANY (ARRAY['pending'::"text", 'processing'::"text", 'parsed'::"text", 'needs_review'::"text", 'failed'::"text"]))),
    CONSTRAINT "receipts_sync_status_check" CHECK (("sync_status" = ANY (ARRAY['pending'::"text", 'synced'::"text", 'conflict'::"text"])))
);


ALTER TABLE "public"."receipts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."shop_aliases" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "raw_name" "text" NOT NULL,
    "shop_id" "uuid",
    "source" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "shop_aliases_source_check" CHECK (("source" = ANY (ARRAY['ocr'::"text", 'crawler'::"text", 'manual'::"text", 'seed'::"text"])))
);


ALTER TABLE "public"."shop_aliases" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."shops" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "canonical_name" "text" NOT NULL,
    "shop_type" "text",
    "region" "text",
    "district" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "shops_shop_type_check" CHECK (("shop_type" = ANY (ARRAY['supermarket'::"text", 'wet_market'::"text", 'pharmacy'::"text", 'convenience'::"text", 'online'::"text", 'restaurant'::"text", 'cafe'::"text", 'takeaway'::"text", 'other'::"text"])))
);


ALTER TABLE "public"."shops" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."store_categories" (
    "id" integer NOT NULL,
    "code" "text" NOT NULL,
    "name_tc" "text" NOT NULL,
    "name_en" "text",
    "description" "text",
    "display_order" integer DEFAULT 0
);


ALTER TABLE "public"."store_categories" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."store_categories_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."store_categories_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."store_categories_id_seq" OWNED BY "public"."store_categories"."id";



CREATE TABLE IF NOT EXISTS "public"."subcategories" (
    "id" integer NOT NULL,
    "code" "text" NOT NULL,
    "name_tc" "text" NOT NULL,
    "name_en" "text",
    "parent_cate" "text",
    "display_order" integer DEFAULT 0
);


ALTER TABLE "public"."subcategories" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."subcategories_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."subcategories_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."subcategories_id_seq" OWNED BY "public"."subcategories"."id";



CREATE TABLE IF NOT EXISTS "public"."weather_signals" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "signal_type" "text" NOT NULL,
    "signal_name" "text",
    "issued_at" timestamp with time zone NOT NULL,
    "expired_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."weather_signals" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."weight_options" (
    "id" integer NOT NULL,
    "subcategory_code" "text" NOT NULL,
    "weight_g" integer NOT NULL,
    "label" "text" NOT NULL,
    "unit_type" "text" DEFAULT 'g'::"text",
    "display_order" integer DEFAULT 0,
    CONSTRAINT "weight_options_unit_type_check" CHECK (("unit_type" = ANY (ARRAY['g'::"text", 'pcs'::"text", 'kg'::"text"])))
);


ALTER TABLE "public"."weight_options" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."weight_options_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."weight_options_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."weight_options_id_seq" OWNED BY "public"."weight_options"."id";



ALTER TABLE ONLY "public"."prd_categories" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."prd_categories_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."price_data" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."price_data_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."store_categories" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."store_categories_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."subcategories" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."subcategories_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."weight_options" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."weight_options_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."app_errors"
    ADD CONSTRAINT "app_errors_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cc_prices"
    ADD CONSTRAINT "cc_prices_pkey" PRIMARY KEY ("cc_code");



ALTER TABLE ONLY "public"."chat_rate_limits"
    ADD CONSTRAINT "chat_rate_limits_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."employer_helper_relations"
    ADD CONSTRAINT "employer_helper_relations_employer_id_helper_id_key" UNIQUE ("employer_id", "helper_id");



ALTER TABLE ONLY "public"."employer_helper_relations"
    ADD CONSTRAINT "employer_helper_relations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."employer_payments"
    ADD CONSTRAINT "employer_payments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."expense_summaries"
    ADD CONSTRAINT "expense_summaries_employer_id_helper_id_month_category_key" UNIQUE ("employer_id", "helper_id", "month", "category");



ALTER TABLE ONLY "public"."expense_summaries"
    ADD CONSTRAINT "expense_summaries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."master_products"
    ADD CONSTRAINT "master_products_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."prd_categories"
    ADD CONSTRAINT "prd_categories_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."prd_categories"
    ADD CONSTRAINT "prd_categories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."price_alert_suppression"
    ADD CONSTRAINT "price_alert_suppression_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."price_alerts"
    ADD CONSTRAINT "price_alerts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."price_data"
    ADD CONSTRAINT "price_data_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."price_history"
    ADD CONSTRAINT "price_history_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."product_aliases"
    ADD CONSTRAINT "product_aliases_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."product_aliases"
    ADD CONSTRAINT "product_aliases_raw_name_key" UNIQUE ("raw_name");



ALTER TABLE ONLY "public"."receipt_items"
    ADD CONSTRAINT "receipt_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."receipts"
    ADD CONSTRAINT "receipts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."shop_aliases"
    ADD CONSTRAINT "shop_aliases_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."shop_aliases"
    ADD CONSTRAINT "shop_aliases_raw_name_key" UNIQUE ("raw_name");



ALTER TABLE ONLY "public"."shops"
    ADD CONSTRAINT "shops_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."store_categories"
    ADD CONSTRAINT "store_categories_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."store_categories"
    ADD CONSTRAINT "store_categories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."subcategories"
    ADD CONSTRAINT "subcategories_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."subcategories"
    ADD CONSTRAINT "subcategories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_profiles"
    ADD CONSTRAINT "user_profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_profiles"
    ADD CONSTRAINT "user_profiles_short_code_key" UNIQUE ("short_code");



ALTER TABLE ONLY "public"."weather_signals"
    ADD CONSTRAINT "weather_signals_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."weight_options"
    ADD CONSTRAINT "weight_options_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_cc_prices_cat2" ON "public"."cc_prices" USING "btree" ("cat2_en");



CREATE INDEX "idx_cc_prices_name_en" ON "public"."cc_prices" USING "btree" ("name_en");



CREATE INDEX "idx_cc_prices_name_zh" ON "public"."cc_prices" USING "btree" ("name_zh");



CREATE INDEX "idx_cc_prices_standard_weight" ON "public"."cc_prices" USING "btree" ("standard_weight_g");



CREATE INDEX "idx_chat_logs_created_at" ON "public"."chat_logs" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_chat_logs_is_expense" ON "public"."chat_logs" USING "btree" ("is_expense");



CREATE INDEX "idx_chat_logs_user_id" ON "public"."chat_logs" USING "btree" ("user_id");



CREATE INDEX "idx_chat_rate_user_exp" ON "public"."chat_rate_limits" USING "btree" ("user_id", "is_expense", "created_at");



CREATE INDEX "idx_chat_rate_user_time" ON "public"."chat_rate_limits" USING "btree" ("user_id", "created_at");



CREATE INDEX "idx_ep_created_by" ON "public"."employer_payments" USING "btree" ("created_by");



CREATE INDEX "idx_ep_payment_date" ON "public"."employer_payments" USING "btree" ("payment_date");



CREATE INDEX "idx_ep_relation_id" ON "public"."employer_payments" USING "btree" ("relation_id");



CREATE INDEX "idx_master_products_cate" ON "public"."master_products" USING "btree" ("prd_cate");



CREATE INDEX "idx_master_products_keywords" ON "public"."master_products" USING "gin" ("search_keywords");



CREATE INDEX "idx_price_history_product_date" ON "public"."price_history" USING "btree" ("master_product_id", "recorded_at");



CREATE INDEX "idx_price_history_region" ON "public"."price_history" USING "btree" ("region", "recorded_at");



CREATE INDEX "idx_price_history_shop" ON "public"."price_history" USING "btree" ("shop_id", "recorded_at");



CREATE INDEX "idx_product_aliases_master" ON "public"."product_aliases" USING "btree" ("master_product_id");



CREATE INDEX "idx_receipt_items_category" ON "public"."receipt_items" USING "btree" ("prd_cate");



CREATE INDEX "idx_receipt_items_receipt_id" ON "public"."receipt_items" USING "btree" ("receipt_id");



CREATE INDEX "idx_receipts_created_by" ON "public"."receipts" USING "btree" ("created_by");



CREATE INDEX "idx_receipts_date_anomaly" ON "public"."receipts" USING "btree" ("date_anomaly");



CREATE INDEX "idx_receipts_parse_status_pending" ON "public"."receipts" USING "btree" ("parse_status") WHERE ("parse_status" = 'pending'::"text");



CREATE INDEX "idx_receipts_transaction_date" ON "public"."receipts" USING "btree" ("transaction_date");



CREATE INDEX "idx_shop_aliases_shop" ON "public"."shop_aliases" USING "btree" ("shop_id");



CREATE INDEX "idx_shops_region" ON "public"."shops" USING "btree" ("region");



CREATE INDEX "idx_shops_type" ON "public"."shops" USING "btree" ("shop_type");



CREATE INDEX "idx_subcategories_parent" ON "public"."subcategories" USING "btree" ("parent_cate");



CREATE INDEX "idx_weight_options_subcategory" ON "public"."weight_options" USING "btree" ("subcategory_code");



CREATE OR REPLACE TRIGGER "on_receipt_inserted" AFTER INSERT ON "public"."receipts" FOR EACH ROW WHEN (("new"."parse_status" = 'pending'::"text")) EXECUTE FUNCTION "public"."handle_new_receipt"();



CREATE OR REPLACE TRIGGER "on_relation_activated" AFTER UPDATE OF "status" ON "public"."employer_helper_relations" FOR EACH ROW EXECUTE FUNCTION "public"."backfill_receipts_on_link"();



CREATE OR REPLACE TRIGGER "update_expense_summaries_updated_at" BEFORE UPDATE ON "public"."expense_summaries" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_receipts_updated_at" BEFORE UPDATE ON "public"."receipts" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_user_profiles_updated_at" BEFORE UPDATE ON "public"."user_profiles" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



ALTER TABLE ONLY "public"."employer_helper_relations"
    ADD CONSTRAINT "employer_helper_relations_employer_id_fkey" FOREIGN KEY ("employer_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."employer_helper_relations"
    ADD CONSTRAINT "employer_helper_relations_helper_id_fkey" FOREIGN KEY ("helper_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."employer_payments"
    ADD CONSTRAINT "employer_payments_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."user_profiles"("id");



ALTER TABLE ONLY "public"."employer_payments"
    ADD CONSTRAINT "employer_payments_employer_id_fkey" FOREIGN KEY ("employer_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."employer_payments"
    ADD CONSTRAINT "employer_payments_helper_id_fkey" FOREIGN KEY ("helper_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."employer_payments"
    ADD CONSTRAINT "employer_payments_relation_id_fkey" FOREIGN KEY ("relation_id") REFERENCES "public"."employer_helper_relations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."expense_summaries"
    ADD CONSTRAINT "expense_summaries_employer_id_fkey" FOREIGN KEY ("employer_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."expense_summaries"
    ADD CONSTRAINT "expense_summaries_helper_id_fkey" FOREIGN KEY ("helper_id") REFERENCES "public"."user_profiles"("id");



ALTER TABLE ONLY "public"."expense_summaries"
    ADD CONSTRAINT "expense_summaries_relation_id_fkey" FOREIGN KEY ("relation_id") REFERENCES "public"."employer_helper_relations"("id");



ALTER TABLE ONLY "public"."price_alerts"
    ADD CONSTRAINT "price_alerts_receipt_id_fkey" FOREIGN KEY ("receipt_id") REFERENCES "public"."receipts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."price_history"
    ADD CONSTRAINT "price_history_master_product_id_fkey" FOREIGN KEY ("master_product_id") REFERENCES "public"."master_products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."price_history"
    ADD CONSTRAINT "price_history_shop_id_fkey" FOREIGN KEY ("shop_id") REFERENCES "public"."shops"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."price_history"
    ADD CONSTRAINT "price_history_source_receipt_id_fkey" FOREIGN KEY ("source_receipt_id") REFERENCES "public"."receipts"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."product_aliases"
    ADD CONSTRAINT "product_aliases_master_product_id_fkey" FOREIGN KEY ("master_product_id") REFERENCES "public"."master_products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."receipt_items"
    ADD CONSTRAINT "receipt_items_cc_code_fkey" FOREIGN KEY ("cc_code") REFERENCES "public"."cc_prices"("cc_code");



ALTER TABLE ONLY "public"."receipt_items"
    ADD CONSTRAINT "receipt_items_master_product_id_fkey" FOREIGN KEY ("master_product_id") REFERENCES "public"."master_products"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."receipt_items"
    ADD CONSTRAINT "receipt_items_prd_cate_fkey" FOREIGN KEY ("prd_cate") REFERENCES "public"."prd_categories"("code");



ALTER TABLE ONLY "public"."receipt_items"
    ADD CONSTRAINT "receipt_items_receipt_id_fkey" FOREIGN KEY ("receipt_id") REFERENCES "public"."receipts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."receipt_items"
    ADD CONSTRAINT "receipt_items_subcategory_code_fkey" FOREIGN KEY ("subcategory_code") REFERENCES "public"."subcategories"("code");



ALTER TABLE ONLY "public"."receipts"
    ADD CONSTRAINT "receipts_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."user_profiles"("id");



ALTER TABLE ONLY "public"."receipts"
    ADD CONSTRAINT "receipts_employer_id_fkey" FOREIGN KEY ("employer_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."receipts"
    ADD CONSTRAINT "receipts_helper_id_fkey" FOREIGN KEY ("helper_id") REFERENCES "public"."user_profiles"("id");



ALTER TABLE ONLY "public"."receipts"
    ADD CONSTRAINT "receipts_relation_id_fkey" FOREIGN KEY ("relation_id") REFERENCES "public"."employer_helper_relations"("id");



ALTER TABLE ONLY "public"."receipts"
    ADD CONSTRAINT "receipts_reviewed_by_fkey" FOREIGN KEY ("reviewed_by") REFERENCES "public"."user_profiles"("id");



ALTER TABLE ONLY "public"."receipts"
    ADD CONSTRAINT "receipts_shop_id_fkey" FOREIGN KEY ("shop_id") REFERENCES "public"."shops"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."receipts"
    ADD CONSTRAINT "receipts_store_cate_fkey" FOREIGN KEY ("store_cate") REFERENCES "public"."store_categories"("code");



ALTER TABLE ONLY "public"."shop_aliases"
    ADD CONSTRAINT "shop_aliases_shop_id_fkey" FOREIGN KEY ("shop_id") REFERENCES "public"."shops"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."subcategories"
    ADD CONSTRAINT "subcategories_parent_cate_fkey" FOREIGN KEY ("parent_cate") REFERENCES "public"."prd_categories"("code");



ALTER TABLE ONLY "public"."user_profiles"
    ADD CONSTRAINT "user_profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."weight_options"
    ADD CONSTRAINT "weight_options_subcategory_code_fkey" FOREIGN KEY ("subcategory_code") REFERENCES "public"."subcategories"("code");



CREATE POLICY "Anyone can read aliases" ON "public"."product_aliases" FOR SELECT USING (true);



CREATE POLICY "Anyone can read aliases" ON "public"."shop_aliases" FOR SELECT USING (true);



CREATE POLICY "Anyone can read master_products" ON "public"."master_products" FOR SELECT USING (true);



CREATE POLICY "Anyone can read price data" ON "public"."price_data" FOR SELECT USING (true);



CREATE POLICY "Anyone can read price_alert_suppression" ON "public"."price_alert_suppression" FOR SELECT USING (true);



CREATE POLICY "Anyone can read price_history" ON "public"."price_history" FOR SELECT USING (true);



CREATE POLICY "Anyone can read shops" ON "public"."shops" FOR SELECT USING (true);



CREATE POLICY "Anyone can read weather_signals" ON "public"."weather_signals" FOR SELECT USING (true);



CREATE POLICY "Authenticated users can insert master_products" ON "public"."master_products" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Employers can manage their relations" ON "public"."employer_helper_relations" USING (("auth"."uid"() = "employer_id"));



CREATE POLICY "Employers can view receipts" ON "public"."receipts" FOR SELECT USING ((("auth"."uid"() = "employer_id") OR ("auth"."uid"() = "helper_id")));



CREATE POLICY "Employers can view summaries" ON "public"."expense_summaries" FOR SELECT USING (("auth"."uid"() = "employer_id"));



CREATE POLICY "Employers can view their helpers" ON "public"."employer_helper_relations" FOR SELECT USING (("auth"."uid"() = "employer_id"));



CREATE POLICY "Helpers can delete own receipts" ON "public"."receipts" FOR DELETE USING (("auth"."uid"() = "helper_id"));



CREATE POLICY "Helpers can delete receipt items" ON "public"."receipt_items" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."receipts"
  WHERE (("receipts"."id" = "receipt_items"."receipt_id") AND ("receipts"."helper_id" = "auth"."uid"())))));



CREATE POLICY "Helpers can insert receipt items for own receipts" ON "public"."receipt_items" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."receipts"
  WHERE (("receipts"."id" = "receipt_items"."receipt_id") AND ("receipts"."helper_id" = "auth"."uid"())))));



CREATE POLICY "Helpers can insert receipts" ON "public"."receipts" FOR INSERT WITH CHECK (("auth"."uid"() = "helper_id"));



CREATE POLICY "Helpers can update own profile" ON "public"."user_profiles" FOR UPDATE USING ((("auth"."uid"() = "id") AND ("role" = 'helper'::"text"))) WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "Helpers can update own receipts" ON "public"."receipts" FOR UPDATE USING (("auth"."uid"() = "helper_id"));



CREATE POLICY "Helpers can update receipt items" ON "public"."receipt_items" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."receipts"
  WHERE (("receipts"."id" = "receipt_items"."receipt_id") AND ("receipts"."helper_id" = "auth"."uid"())))));



CREATE POLICY "Helpers can view their employers" ON "public"."employer_helper_relations" FOR SELECT USING (("auth"."uid"() = "helper_id"));



CREATE POLICY "Helpers_can_delete_receipt_items" ON "public"."receipt_items" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."receipts"
  WHERE (("receipts"."id" = "receipt_items"."receipt_id") AND ("receipts"."helper_id" = "auth"."uid"())))));



CREATE POLICY "Helpers_can_insert_receipt_items" ON "public"."receipt_items" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."receipts"
  WHERE (("receipts"."id" = "receipt_items"."receipt_id") AND ("receipts"."helper_id" = "auth"."uid"()) AND ("receipts"."relation_id" IS NOT NULL)))));



CREATE POLICY "Helpers_can_update_receipt_items" ON "public"."receipt_items" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."receipts"
  WHERE (("receipts"."id" = "receipt_items"."receipt_id") AND ("receipts"."helper_id" = "auth"."uid"())))));



CREATE POLICY "Service can manage price data" ON "public"."price_data" USING ((("auth"."jwt"() ->> 'role'::"text") = 'service_role'::"text"));



CREATE POLICY "Service role can insert price_history" ON "public"."price_history" FOR INSERT WITH CHECK ((("auth"."role"() = 'service_role'::"text") OR ("auth"."uid"() IS NOT NULL)));



CREATE POLICY "Service role can manage aliases" ON "public"."product_aliases" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "Service role can manage aliases" ON "public"."shop_aliases" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "Service role can manage master_products" ON "public"."master_products" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "Service role can manage price_alert_suppression" ON "public"."price_alert_suppression" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "Service role can manage shops" ON "public"."shops" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "Service role can manage weather_signals" ON "public"."weather_signals" USING (("auth"."role"() = 'service_role'::"text")) WITH CHECK (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "Users can insert own profile" ON "public"."user_profiles" FOR INSERT WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "Users can update own master_products" ON "public"."master_products" FOR UPDATE TO "authenticated" USING (("auth"."uid"() IS NOT NULL)) WITH CHECK (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can update own profile" ON "public"."user_profiles" FOR UPDATE USING (("auth"."uid"() = "id"));



CREATE POLICY "Users can update own receipt_items master_product_id" ON "public"."receipt_items" FOR UPDATE USING (("auth"."uid"() = ( SELECT "receipts"."helper_id"
   FROM "public"."receipts"
  WHERE ("receipts"."id" = "receipt_items"."receipt_id")))) WITH CHECK (("auth"."uid"() = ( SELECT "receipts"."helper_id"
   FROM "public"."receipts"
  WHERE ("receipts"."id" = "receipt_items"."receipt_id"))));



CREATE POLICY "Users can view own profile" ON "public"."user_profiles" FOR SELECT USING (("auth"."uid"() = "id"));



CREATE POLICY "Users can view receipt items" ON "public"."receipt_items" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."receipts"
  WHERE (("receipts"."id" = "receipt_items"."receipt_id") AND (("receipts"."employer_id" = "auth"."uid"()) OR ("receipts"."helper_id" = "auth"."uid"()))))));



CREATE POLICY "Users can view their alerts" ON "public"."price_alerts" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."receipts"
  WHERE (("receipts"."id" = "price_alerts"."receipt_id") AND (("receipts"."employer_id" = "auth"."uid"()) OR ("receipts"."helper_id" = "auth"."uid"()))))));



CREATE POLICY "Users_can_view_receipt_items" ON "public"."receipt_items" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."receipts"
  WHERE (("receipts"."id" = "receipt_items"."receipt_id") AND (("receipts"."employer_id" = "auth"."uid"()) OR ("receipts"."helper_id" = "auth"."uid"()))))));



CREATE POLICY "allow_authenticated_insert_app_errors" ON "public"."app_errors" FOR INSERT WITH CHECK (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "allow_authenticated_insert_master_products" ON "public"."master_products" FOR INSERT WITH CHECK (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "allow_authenticated_insert_product_aliases" ON "public"."product_aliases" FOR INSERT WITH CHECK (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "allow_authenticated_insert_shop_aliases" ON "public"."shop_aliases" FOR INSERT WITH CHECK (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "allow_authenticated_insert_shops" ON "public"."shops" FOR INSERT WITH CHECK (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "allow_authenticated_select_app_errors" ON "public"."app_errors" FOR SELECT USING (("auth"."role"() = 'authenticated'::"text"));



ALTER TABLE "public"."app_errors" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."chat_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."employer_helper_relations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."expense_summaries" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."master_products" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."price_alert_suppression" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."price_alerts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."price_data" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."price_history" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."product_aliases" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."receipt_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."receipts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "service_role_all" ON "public"."chat_logs" USING (true) WITH CHECK (true);



ALTER TABLE "public"."shop_aliases" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."shops" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "users_insert_own" ON "public"."chat_logs" FOR INSERT WITH CHECK ((("auth"."uid"())::"text" = "user_id"));



CREATE POLICY "users_read_own" ON "public"."chat_logs" FOR SELECT USING ((("auth"."uid"())::"text" = "user_id"));



ALTER TABLE "public"."weather_signals" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."receipts";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";

























































































































































GRANT ALL ON FUNCTION "public"."backfill_receipts_on_link"() TO "anon";
GRANT ALL ON FUNCTION "public"."backfill_receipts_on_link"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."backfill_receipts_on_link"() TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_short_code"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_short_code"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_short_code"() TO "service_role";



GRANT ALL ON TABLE "public"."user_profiles" TO "anon";
GRANT ALL ON TABLE "public"."user_profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."user_profiles" TO "service_role";



GRANT ALL ON FUNCTION "public"."get_employer_by_code"("p_code" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_employer_by_code"("p_code" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_employer_by_code"("p_code" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_price_alert"("p_category" "text", "p_price" real) TO "anon";
GRANT ALL ON FUNCTION "public"."get_price_alert"("p_category" "text", "p_price" real) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_price_alert"("p_category" "text", "p_price" real) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_price_alert"("p_category" "text", "p_price" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."get_price_alert"("p_category" "text", "p_price" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_price_alert"("p_category" "text", "p_price" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_receipt"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_receipt"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_receipt"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON TABLE "public"."employer_helper_relations" TO "anon";
GRANT ALL ON TABLE "public"."employer_helper_relations" TO "authenticated";
GRANT ALL ON TABLE "public"."employer_helper_relations" TO "service_role";



GRANT ALL ON FUNCTION "public"."link_helper_to_employer_via_code"("p_employer_code" "uuid", "p_helper_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."link_helper_to_employer_via_code"("p_employer_code" "uuid", "p_helper_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."link_helper_to_employer_via_code"("p_employer_code" "uuid", "p_helper_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."parse_receipt_text"("p_raw_text" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."parse_receipt_text"("p_raw_text" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."parse_receipt_text"("p_raw_text" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_receipt_shop"("p_receipt_id" "uuid", "p_shop_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."set_receipt_shop"("p_receipt_id" "uuid", "p_shop_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_receipt_shop"("p_receipt_id" "uuid", "p_shop_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."test_trigger"() TO "anon";
GRANT ALL ON FUNCTION "public"."test_trigger"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."test_trigger"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_receipt_shop"("p_receipt_id" "uuid", "p_shop_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."update_receipt_shop"("p_receipt_id" "uuid", "p_shop_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_receipt_shop"("p_receipt_id" "uuid", "p_shop_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "service_role";



GRANT ALL ON FUNCTION "public"."upsert_cc_prices"("records" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."upsert_cc_prices"("records" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."upsert_cc_prices"("records" "jsonb") TO "service_role";


















GRANT ALL ON TABLE "public"."app_errors" TO "anon";
GRANT ALL ON TABLE "public"."app_errors" TO "authenticated";
GRANT ALL ON TABLE "public"."app_errors" TO "service_role";



GRANT ALL ON TABLE "public"."cc_prices" TO "anon";
GRANT ALL ON TABLE "public"."cc_prices" TO "authenticated";
GRANT ALL ON TABLE "public"."cc_prices" TO "service_role";



GRANT ALL ON TABLE "public"."chat_logs" TO "anon";
GRANT ALL ON TABLE "public"."chat_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."chat_logs" TO "service_role";



GRANT ALL ON TABLE "public"."chat_rate_limits" TO "anon";
GRANT ALL ON TABLE "public"."chat_rate_limits" TO "authenticated";
GRANT ALL ON TABLE "public"."chat_rate_limits" TO "service_role";



GRANT ALL ON TABLE "public"."employer_payments" TO "anon";
GRANT ALL ON TABLE "public"."employer_payments" TO "authenticated";
GRANT ALL ON TABLE "public"."employer_payments" TO "service_role";



GRANT ALL ON TABLE "public"."expense_summaries" TO "anon";
GRANT ALL ON TABLE "public"."expense_summaries" TO "authenticated";
GRANT ALL ON TABLE "public"."expense_summaries" TO "service_role";



GRANT ALL ON TABLE "public"."master_products" TO "anon";
GRANT ALL ON TABLE "public"."master_products" TO "authenticated";
GRANT ALL ON TABLE "public"."master_products" TO "service_role";



GRANT ALL ON TABLE "public"."prd_categories" TO "anon";
GRANT ALL ON TABLE "public"."prd_categories" TO "authenticated";
GRANT ALL ON TABLE "public"."prd_categories" TO "service_role";



GRANT ALL ON SEQUENCE "public"."prd_categories_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."prd_categories_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."prd_categories_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."price_alert_suppression" TO "anon";
GRANT ALL ON TABLE "public"."price_alert_suppression" TO "authenticated";
GRANT ALL ON TABLE "public"."price_alert_suppression" TO "service_role";



GRANT ALL ON TABLE "public"."price_alerts" TO "anon";
GRANT ALL ON TABLE "public"."price_alerts" TO "authenticated";
GRANT ALL ON TABLE "public"."price_alerts" TO "service_role";



GRANT ALL ON TABLE "public"."price_data" TO "anon";
GRANT ALL ON TABLE "public"."price_data" TO "authenticated";
GRANT ALL ON TABLE "public"."price_data" TO "service_role";



GRANT ALL ON SEQUENCE "public"."price_data_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."price_data_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."price_data_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."price_history" TO "anon";
GRANT ALL ON TABLE "public"."price_history" TO "authenticated";
GRANT ALL ON TABLE "public"."price_history" TO "service_role";



GRANT ALL ON TABLE "public"."product_aliases" TO "anon";
GRANT ALL ON TABLE "public"."product_aliases" TO "authenticated";
GRANT ALL ON TABLE "public"."product_aliases" TO "service_role";



GRANT ALL ON TABLE "public"."receipt_items" TO "anon";
GRANT ALL ON TABLE "public"."receipt_items" TO "authenticated";
GRANT ALL ON TABLE "public"."receipt_items" TO "service_role";



GRANT ALL ON TABLE "public"."receipts" TO "anon";
GRANT ALL ON TABLE "public"."receipts" TO "authenticated";
GRANT ALL ON TABLE "public"."receipts" TO "service_role";



GRANT ALL ON TABLE "public"."shop_aliases" TO "anon";
GRANT ALL ON TABLE "public"."shop_aliases" TO "authenticated";
GRANT ALL ON TABLE "public"."shop_aliases" TO "service_role";



GRANT ALL ON TABLE "public"."shops" TO "anon";
GRANT ALL ON TABLE "public"."shops" TO "authenticated";
GRANT ALL ON TABLE "public"."shops" TO "service_role";



GRANT ALL ON TABLE "public"."store_categories" TO "anon";
GRANT ALL ON TABLE "public"."store_categories" TO "authenticated";
GRANT ALL ON TABLE "public"."store_categories" TO "service_role";



GRANT ALL ON SEQUENCE "public"."store_categories_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."store_categories_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."store_categories_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."subcategories" TO "anon";
GRANT ALL ON TABLE "public"."subcategories" TO "authenticated";
GRANT ALL ON TABLE "public"."subcategories" TO "service_role";



GRANT ALL ON SEQUENCE "public"."subcategories_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."subcategories_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."subcategories_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."weather_signals" TO "anon";
GRANT ALL ON TABLE "public"."weather_signals" TO "authenticated";
GRANT ALL ON TABLE "public"."weather_signals" TO "service_role";



GRANT ALL ON TABLE "public"."weight_options" TO "anon";
GRANT ALL ON TABLE "public"."weight_options" TO "authenticated";
GRANT ALL ON TABLE "public"."weight_options" TO "service_role";



GRANT ALL ON SEQUENCE "public"."weight_options_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."weight_options_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."weight_options_id_seq" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";































