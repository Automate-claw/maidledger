# MaidLedger 架構文檔

> ⚠️ 每次修改架構（新增/移動/刪除 component）後，必須更新此文檔。
> 此文檔係Developer's工作指引，搵唔到嘢時先睇呢份。

---

## 🗺️ 架構總覽

```
┌─────────────────────────────────────────────────────────────┐
│                         CLIENTS                              │
├─────────────────────────┬───────────────────────────────────┤
│   employer_app (Flutter)│      helper_app (Flutter)        │
│   apps/employer_app/    │      apps/helper_app/             │
└─────────────────────────┴───────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    SUPABASE PLATFORM                         │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              EDGE FUNCTIONS (Backend Logic)          │   │
│  │                                                      │   │
│  │  ┌─────────────┐  ┌──────────────┐  ┌─────────────┐  │   │
│  │  │ chat-      │  │ receipt-     │  │ product-    │  │   │
│  │  │ orchestrate│  │ orchestrate  │  │ manager     │  │   │
│  │  │ ⭐ main    │  │              │  │             │  │   │
│  │  └─────────────┘  └──────────────┘  └─────────────┘  │   │
│  │                                                      │   │
│  │  ┌─────────────┐  ┌──────────────┐  ┌─────────────┐  │   │
│  │  │ receipt-   │  │ receipt-     │  │ shop-       │  │   │
│  │  │ parse      │  │ writer       │  │ manager     │  │   │
│  │  │ (new)      │  │              │  │             │  │   │
│  │  └─────────────┘  └──────────────┘  └─────────────┘  │   │
│  │                                                      │   │
│  │  ┌─────────────┐  ┌──────────────┐  ┌─────────────┐  │   │
│  │  │ chat-parser │  │ receipt-     │  │ price-alert│  │   │
│  │  │ (legacy)    │  │ parser       │  │ -engine    │  │   │
│  │  └─────────────┘  └──────────────┘  └─────────────┘  │   │
│  │                                                      │   │
│  │  ┌─────────────┐  ┌──────────────┐                   │   │
│  │  │ notification│  │ weather-     │                   │   │
│  │  │ -broadcast  │  │ check        │                   │   │
│  │  └─────────────┘  └──────────────┘                   │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              DATABASE (PostgreSQL via PostgREST)     │   │
│  │  • products  • shops  • receipts  • price_history    │   │
│  │  • employers  • helpers  • payments                 │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              STORAGE (File uploads)                  │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘

        │
        ▼

┌─────────────────────────────┐
│   SCRAPER (Python + Playwright)  │
│   services/scraper/              │
│   定時爬蟲，更新商品價格         │
└─────────────────────────────┘
```

---

## 📁 資料夾結構

```
maidledger/
├── apps/
│   ├── employer_app/        # 僱主 App（Flutter）
│   │   └── lib/             # 主要 Dart 代碼
│   └── helper_app/          # 工人 App（Flutter）
│       ├── lib/             # 主要 Dart 代碼
│       └── supabase/        # 本地 Supabase 配置
│
├── supabase/
│   ├── functions/           # ⭐ Edge Functions（主要後端邏輯）
│   │   ├── chat-orchestrate/     # ⭐ 主力：整合 chat-parser + receipt-writer
│   │   ├── receipt-orchestrate/  # receipt 多步驟流程協調
│   │   ├── receipt-parse/        # 新版 receipt 解析（HTTP-triggered）
│   │   ├── receipt-writer/       # 寫入 receipt 到 DB
│   │   ├── shop-manager/         # 商戶 matching + 管理
│   │   ├── product-manager/      # 商品 master data
│   │   ├── chat-parser/          # 舊版 chat 解析（逐漸被取代）
│   │   ├── receipt-parser/       # 舊版 receipt 解析
│   │   ├── price-alert-engine/   # 價格警報引擎
│   │   ├── notification-broadcast/  # 通知廣播
│   │   └── weather-check/        # 天氣檢查
│   │
│   └── migrations/          # Database migrations
│
├── services/
│   ├── scraper/             # Python 爬蟲服務
│   │   └── src/             # 爬蟲代碼
│   └── supabase/            # (empty/研究用)
│
├── packages/
│   ├── receipt-parser/      # Dart receipt 解析 package
│   ├── localization/        # 本地化 package
│   └── archive/             # 舊代码（已棄用）
│       ├── ai-booking-agent/
│       ├── price-alert-engine/
│       └── receipt-scanner/
│
└── docs/
    ├── SCHEMA.html          # 數據庫 Schema 圖
    └── *.md                 # 設計文檔
```

---

## 🎯 Component → 資料夾 對照表

| Component | 路徑 | 用途 |
|---|---|---|
| **Chat flow** | `supabase/functions/chat-orchestrate/` | 主力整合點，接收文字→解析→寫入 |
| **Receipt flow** | `supabase/functions/receipt-orchestrate/` | 多步驟协调（lock→patch→rpc） |
| **Receipt parse** | `supabase/functions/receipt-parse/` | 新版 receipt OCR 解析 |
| **Receipt write** | `supabase/functions/receipt-writer/` | 寫入 receipts 表 |
| **Shop matching** | `supabase/functions/shop-manager/` | 商戶名稱 canonical + matching |
| **Product matching** | `supabase/functions/product-manager/` | 商品 master data + brand |
| **Employer App** | `apps/employer_app/lib/` | 僱主 Flutter App |
| **Helper App** | `apps/helper_app/lib/` | 工人 Flutter App |
| **Scraper** | `services/scraper/src/` | Python 爬蟲（定時更新價格） |
| **DB Schema** | `docs/SCHEMA.html` | 數據庫 ERD 圖 |

---

## 🔄 常用工作流程

### 修補 Flutter App
```
apps/employer_app/lib/   ← 僱主
apps/helper_app/lib/     ← 工人
```

### 修補 Backend (Edge Function)
```
supabase/functions/<function-name>/
```
例如：`supabase/functions/receipt-parse/index.ts`

### 修補 Scraper
```
services/scraper/src/
```

### 更新 Schema
```
supabase/migrations/           ← SQL migrations
docs/SCHEMA.html              ← 可視化圖（手動更新）
```

---

## 📝 更新日誌

| 日期 | 更新内容 |
|---|---|
| 2026-05-24 | 初始架構文檔建立 |

---

## 💡 使用建議

1. **每次開始新任務前**，先睇呢份 doc 確認目標資料夾
2. **架構變更後**，立即更新「Component → 資料夾」對照表
3. **SCHEMA.html** 係數據庫視圖，需要手動同步更新

---

*最後更新：2026-05-24*