# MaidLedger MVP — 技術規格書

**最後更新：** 2026-05-13  
**狀態：** 🟡 Phase 1 進行中

---

## 📋 總覽

| 項目 | 內容 |
|------|------|
| 產品名稱 | MaidLedger |
| 目標用戶 | 僱主 + 外傭 (FDW) |
| 核心功能 | 智能收據掃描 + AI 對話記帳 + 價格警告 |
| 平台 | Flutter (Cross-platform) |
| Backend | Supabase (PostgreSQL + Edge Functions) |

---

## 🛠️ Tech Stack

| 層 | 選擇 |
|---|---|
| Mobile | Flutter |
| Backend | Supabase |
| Database | PostgreSQL |
| ORM | Prisma-style queries via Supabase client |
| LLM (Receipt解析) | Gemini 1.5 Flash |
| LLM (對話式記帳) | Gemini 1.5 Flash |
| OCR | Google ML Kit (On-device) |
| Scraper | Python + Playwright |
| 部署 | Vercel (Frontend) / Railway (Scraper) |

---

## 📁 目錄結構

```
maidledger/
├── apps/
│   ├── helper_app/          # Flutter (外傭)
│   └── employer_app/        # Flutter (僱主)
├── packages/
│   ├── receipt-scanner/     # ML Kit + Sync Service
│   ├── ai-booking-agent/    # Keyword engine + Gemini
│   └── price-alert-engine/  # (in progress)
├── services/
│   ├── scraper/             # Python crawler
│   └── supabase/           # Edge Functions + migrations
└── tests/
```

---

## 🔌 API 設計 (Supabase)

### Tables

```sql
-- 收據表
CREATE TABLE receipts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employer_id UUID REFERENCES auth.users NOT NULL,
  helper_id UUID REFERENCES auth.users,
  raw_text TEXT NOT NULL,
  parsed_data JSONB,
  amount DECIMAL(10,2),
  category TEXT,
  image_path TEXT,           -- 本地路徑，不上傳
  sync_status TEXT DEFAULT 'pending',
  local_timestamp BIGINT NOT NULL,
  server_timestamp BIGINT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 價格數據表
CREATE TABLE price_data (
  id SERIAL PRIMARY KEY,
  supermarket TEXT NOT NULL,  -- 'hktvmall', 'wellcome', 'parknshop'
  category TEXT NOT NULL,    -- 'fish', 'pork', 'beef', 'chicken', 'vegetables'
  product_name TEXT NOT NULL,
  price DECIMAL(10,2) NOT NULL,
  unit TEXT,
  source_url TEXT,
  scraped_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(supermarket, category, product_name, DATE(scraped_at))
);

-- 用戶表 (extends Supabase auth.users)
CREATE TABLE user_profiles (
  id UUID PRIMARY KEY REFERENCES auth.users,
  role TEXT NOT NULL,         -- 'employer' | 'helper'
  name TEXT,
  phone TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
```

### Edge Functions

| Function | 用途 |
|----------|------|
| `get_price_alert` | 實時價格比對 |
| `parse_receipt_text` | Gemini LLM 解析收據 |
| `sync_receipt` | 離線數據同步 |

---

## 🔄 離線同步策略 (Timestamp-based)

```
1. 用戶影相 → ML Kit OCR → 提取文字
2. 本地 SQLite 儲存 (sync_status: 'pending')
3. 加入 Sync Queue
4. 連網時自動同步 → Supabase
5. 衝突解決：server_timestamp 優先
```

### Sync Queue Schema
```sql
CREATE TABLE sync_queue (
  id TEXT PRIMARY KEY,
  table_name TEXT NOT NULL,
  record_id TEXT NOT NULL,
  action TEXT NOT NULL,      -- 'upsert' | 'delete'
  payload TEXT NOT NULL,
  local_timestamp BIGINT NOT NULL,
  server_timestamp BIGINT,
  synced INTEGER DEFAULT 0,
  created_at BIGINT NOT NULL
);
```

---

## 📱 Phase 1 驗收標準

### receipt-scanner
- [ ] ML Kit 端側識別 < 500ms
- [ ] 離線時正常運作
- [ ] 只上傳 extracted text（唔上傳圖片）
- [ ] 推送通知俾僱主確認

### ai-booking-agent
- [ ] 關鍵詞觸發準確率 > 85%
- [ ] 支援 5 種語言（粵/英/菲/印尼/緬甸）
- [ ] 失敗時 fallback 到結構化輸入

### price-alert-engine
- [ ] 即時價格比對 < 500ms
- [ ] 顯示：超市均價 vs 購買價 vs 街市均價
- [ ] 相對差距百分比呈現

### price-scraper
- [ ] 每日更新
- [ ] 覆蓋主要魚類/肉類/蔬菜

---

## ⚠️ 待確認 / 進行中

1. ✅ Flutter SDK at /home/joe-s-openclaw/flutter
2. ✅ receipt-scanner — ML Kit integration scaffolded
3. ✅ ai-booking-agent — Gemini keyword engine scaffolded
4. 🟡 price-scraper — Python crawler ready for testing
5. 🟡 helper_app — Scaffolded (main.dart + navigation)
6. ⬜ employer_app — Not started
7. ⬜ price-alert-engine — Needs Supabase project
8. ⬜ Offline sync — Needs integration testing

---

## 📅 開發順序

```
Phase 1 (進行中)
├── receipt-scanner ✅ 80%
├── ai-booking-agent ✅ 80%
├── price-alert-engine 🟡 30%
└── price-scraper ✅ 60%

Phase 2 (待開始)
├── employer_app
├── helper_app (完整版)
└── worker-plaza

Phase 3 (待開始)
└── Wet market relative pricing
```

---

## 🔗 外部依賴

| Service | API Key 需求 |
|---------|-------------|
| Google ML Kit | Firebase project |
| Gemini API | Google AI Studio |
| Supabase | Project URL + anon key |
| Google Translate | (可選，fallback) |