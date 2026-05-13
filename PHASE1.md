# MaidLedger Phase 1 — 核心差異化

## 已確認 Tech Stack

| 層 | 選擇 |
|---|---|
| Mobile | Flutter (cross-platform) |
| Backend | Supabase (PostgreSQL + Edge Functions) |
| LLM | Gemini 1.5 Flash (receipt解析) + GPT-4o mini (對話) |
| OCR | Google ML Kit (On-device) |
| Scraper | Python + Playwright |

## Phase 1 Components

### 1. receipt-scanner
- ML Kit 端側 OCR，即時識別
- 離線優先：SQLite 本地存儲 + Timestamp sync
- 只上傳 extracted text（唔上傳圖片）

### 2. ai-booking-agent
- 多語言輸入（粵/英/菲/印尼/緬甸）
- 關鍵詞引擎 + Gemini 1.5 Flash fallback
- 對話式記帳

### 3. price-alert-engine
- 爬蟲數據實時比對
- Supabase Edge Functions 處理
- 顯示：超市均價 vs 購買價 vs 街市均價

### 4. price-scraper (Phase 1)
- Python + Playwright
- 目標：HKTVmall / 惠康 / 百佳
- 每日 Cron job 更新

## 目錄結構

```
maidledger/
├── apps/
│   ├── helper_app/          # Flutter (外傭)
│   └── employer_app/        # Flutter (僱主)
├── packages/
│   ├── receipt-scanner/
│   ├── ai-booking-agent/
│   └── price-alert-engine/
├── services/
│   ├── scraper/             # Python crawler
│   └── supabase/            # Edge Functions + DB schema
└── tests/
```

## 狀態

🟡 Phase 1 進行中