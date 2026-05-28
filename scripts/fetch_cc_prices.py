#!/usr/bin/env python3
"""
fetch-cc-prices: Local script to fetch Consumer Council data and insert to Supabase

Usage:
    python3 scripts/fetch_cc_prices.py

Cron (recommended):
    0 5 * * * cd /path/to/maidledger && python3 scripts/fetch_cc_prices.py
"""

import json
import re
import urllib.request
import subprocess
import os
from datetime import datetime

CC_JSON_URL = "https://online-price-watch.consumer.org.hk/opw/opendata/pricewatch.json"
PROJECT_DIR = os.path.dirname(os.path.abspath(__file__))


def extract_weight(name_str: str) -> int | None:
    """Extract weight in grams from product name"""
    patterns = [
        (r'(\d+)\s*g\b', 1),
        (r'(\d+)\s*公斤', 1000),
        (r'([\d.]+)\s*斤', 604.79),
        (r'([\d.]+)\s*兩', 37.8),
        (r'(\d+)\s*磅', 453.6),
        (r'(\d+)\s*oz', 28.35),
    ]
    for pattern, multiplier in patterns:
        match = re.search(pattern, name_str, re.IGNORECASE)
        if match:
            return int(float(match.group(1)) * multiplier)
    return None


def calculate_price_per_100g(price: float, weight_g: int) -> float | None:
    if not weight_g:
        return None
    return round(price / weight_g * 100, 2)


def fetch_cc_data() -> list[dict]:
    """Fetch CC JSON data"""
    print(f"Fetching CC data from {CC_JSON_URL}")
    req = urllib.request.Request(CC_JSON_URL, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req, timeout=30) as response:
        data = json.loads(response.read().decode('utf-8'))
    print(f"Fetched {len(data)} products")
    return data


def process_product(product: dict) -> dict | None:
    """Process single product into cc_prices format"""
    try:
        cc_code = product.get('code', '')
        if not cc_code:
            return None

        name = product.get('name', {}) or {}
        brand = product.get('brand', {}) or {}
        cat1 = product.get('cat1Name', {}) or {}
        cat2 = product.get('cat2Name', {}) or {}
        cat3 = product.get('cat3Name', {}) or {}
        prices_list = product.get('prices', []) or []

        prices_dict = {}
        for p in prices_list:
            if isinstance(p, dict) and 'supermarketCode' in p and 'price' in p:
                prices_dict[p['supermarketCode']] = float(p['price'])

        name_en = name.get('en', '') or ''
        name_zh = name.get('zh-Hant', '') or ''
        standard_weight_g = extract_weight(f"{name_en} {name_zh}")

        price_per_100g = None
        if prices_dict and standard_weight_g:
            avg_price = sum(prices_dict.values()) / len(prices_dict)
            price_per_100g = calculate_price_per_100g(avg_price, standard_weight_g)

        return {
            'cc_code': cc_code,
            'name_en': name_en,
            'name_zh': name_zh,
            'brand_en': brand.get('en', '') or '',
            'brand_zh': brand.get('zh-Hant', '') or '',
            'cat1_en': cat1.get('en', '') or '',
            'cat1_zh': cat1.get('zh-Hant', '') or '',
            'cat2_en': cat2.get('en', '') or '',
            'cat2_zh': cat2.get('zh-Hant', '') or '',
            'cat3_en': cat3.get('en', '') or '',
            'cat3_zh': cat3.get('zh-Hant', '') or '',
            'prices': json.dumps(prices_dict),
            'standard_weight_g': standard_weight_g,
            'price_per_100g': price_per_100g,
            'updated_at': datetime.utcnow().isoformat()
        }
    except Exception as e:
        return None


def generate_sql_insert(records: list[dict]) -> str:
    """Generate SQL INSERT statements"""
    sql_lines = []
    
    # Clear existing data (REPLACE strategy)
    sql_lines.append("DELETE FROM cc_prices;")
    sql_lines.append("")
    
    # INSERT all records
    sql_lines.append("INSERT INTO cc_prices (cc_code, name_en, name_zh, brand_en, brand_zh, cat1_en, cat1_zh, cat2_en, cat2_zh, cat3_en, cat3_zh, prices, standard_weight_g, price_per_100g, updated_at) VALUES")
    
    values = []
    for r in records:
        val = f"('{r['cc_code']}', " \
              f"'{_escape(r['name_en'])}', " \
              f"'{_escape(r['name_zh'])}', " \
              f"'{_escape(r['brand_en'])}', " \
              f"'{_escape(r['brand_zh'])}', " \
              f"'{_escape(r['cat1_en'])}', " \
              f"'{_escape(r['cat1_zh'])}', " \
              f"'{_escape(r['cat2_en'])}', " \
              f"'{_escape(r['cat2_zh'])}', " \
              f"'{_escape(r['cat3_en'])}', " \
              f"'{_escape(r['cat3_zh'])}', " \
              f"'{_escape(r['prices'])}', " \
              f"{r['standard_weight_g'] or 'NULL'}, " \
              f"{r['price_per_100g'] or 'NULL'}, " \
              f"'{r['updated_at']}')"
        values.append(val)
    
    sql_lines.append(",\n".join(values) + ";")
    
    return "\n".join(sql_lines)


def _escape(s: str) -> str:
    """Escape single quotes for SQL"""
    if s is None:
        return ""
    return str(s).replace("'", "''")


def run_sql(records: list[dict]) -> bool:
    """Insert records via Supabase REST API"""
    supabase_url = "https://hnyazfrkzpxdjiyfzemm.supabase.co"
    service_key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhueWF6ZnJrenB4ZGppeWZ6ZW1tIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3ODY1NTAyNywiZXhwIjoyMDk0MjMxMDI3fQ.ZVG6pRg19IHHne1yyCwvAK5pB0xcA-csnYyYZzzB3kE"
    
    import urllib.request
    import json
    
    url = f"{supabase_url}/rest/v1/cc_prices"
    
    # Upsert with conflict handling
    data = json.dumps(records).encode('utf-8')
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            'Content-Type': 'application/json',
            'apikey': service_key,
            'Authorization': f'Bearer {service_key}',
            'Prefer': 'resolution=merge-duplicates,return=representation'
        },
        method='POST'
    )
    
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            return response.status in [200, 201]
    except urllib.error.HTTPError as e:
        body = e.read().decode('utf-8')[:500]
        print(f"HTTP {e.code}: {body}")
        return False
    except Exception as e:
        print(f"API Error: {e}")
        return False


def main():
    print("=== fetch-cc-prices started ===")
    start = datetime.now()
    
    try:
        # Step 1: Fetch data
        cc_data = fetch_cc_data()
        
        # Step 2: Process
        processed = [p for p in (process_product(x) for x in cc_data) if p]
        print(f"Processed {len(processed)} products")
        
        # Step 3: Insert via REST API
        print("Inserting to Supabase...")
        if run_sql(processed):
            elapsed = (datetime.now() - start).total_seconds()
            print(f"=== SUCCESS in {elapsed:.1f}s ===")
            print(f"Inserted {len(processed)} records")
        else:
            print("=== FAILED: API call failed ===")
            
    except Exception as e:
        print(f"ERROR: {e}")
        raise


if __name__ == "__main__":
    main()