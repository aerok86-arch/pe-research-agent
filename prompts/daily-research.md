You are running a scheduled daily PE research job. Follow CLAUDE.md strictly.

## Today's Task

Produce today's daily PE/Buyout research report and save it to the Notion "📰 Daily Research Reports" database.

## Steps (execute in order, be efficient)

### Step 1. Create placeholder page in Notion
- Call Notion MCP `notion-create-pages` with parent data_source_id `6bf9db7b-de9d-4260-acbe-9bfab9169d98`
- Properties:
  - `제목`: `Daily Research · YYYY-MM-DD` (use today's date in KST)
  - `date:날짜:start`: today's date (YYYY-MM-DD)
  - `date:날짜:is_datetime`: 0
  - `상태`: `진행 중`
  - `읽음`: `__NO__`
- Content: minimal — `# Daily Research · YYYY-MM-DD\n\n🔄 리서치 진행 중...`
- **Store the returned page_id.** You will update this page in Step 5.

### Step 2. Tier 1 source scan (parallel where possible)

Run web searches on these topics/sources for today's news (use `today` or recent-focused queries):

1. `private equity deals announced today` OR `PE buyout news today`
2. `private equity fundraising news this week`
3. `Torsten Slok daily spark` OR `Apollo academy` (latest)
4. `FT Due Diligence PE newsletter` (latest issue)
5. `The Drawdown private equity operations` (latest)
6. `Accordion insights private equity CFO` (recent)
7. `McKinsey private markets private equity` (recent)
8. `Bain private equity insights` (recent)

Fetch full articles for the most relevant 4-6 results via `web_fetch`.

### Step 3. Korea PE scan

Run web searches in Korean:
1. `한국 PE 사모펀드 딜 오늘` OR `인베스트조선 오늘` OR `더벨 PEF`
2. `MBK Hahn IMM STIC 최근 딜` (or related Korean GP names)
3. `KRX 블록딜 CB RCPS 공시` (전일 기준)
4. `금감원 금융위 PEF 규제` (최근)

Fetch 2-3 most relevant articles.

### Step 4. Operational / Value Creation scan

- Search for recent posts from: AlixPartners, Simon-Kucher, Alvarez & Marsal, BluWave podcast episodes
- Look for anything published in the last 7 days about PE operational improvement, pricing, cost, working capital, or portfolio company digital transformation
- This section MUST have substantive content (3+ items minimum)

### Step 5. Assemble and update the report

Call Notion MCP to update the page created in Step 1. Use `notion-update-page` equivalent or append blocks. Full content in Korean 음슴체 following the structure defined in CLAUDE.md:

```
# Daily PE / Buyout Research · YYYY-MM-DD

## ⚡️ TL;DR
- 포인트 1
- 포인트 2  
- 포인트 3

## 🌏 Macro & Market Snapshot
...

## 💼 Deals & Transactions
### Global
...
### Korea (KRX · 비상장)
...

## 💰 Fundraising
...

## 🛠 Value Creation / Operational Insights
### 신규 리포트/아티클
...
### Operating Lever 인사이트
...
### Key Takeaway
...

## 📜 Regulatory & Policy
...

## 🎙 Notable Reads & Listens
...

## 🇰🇷 Korea Focus
...

## ✅ Action Items
- [ ] ...
- [ ] ...

## 📎 Source Coverage
- 소스 A (URL)
- 소스 B (URL)
...
```

### Step 6. Finalize metadata

Update the Notion page properties:
- `상태`: `완료`
- `TL;DR`: 3줄 요약 (모바일 푸시에 노출됨, 간결하게)
- `중요도`: High / Medium / Low (자가 판단: 오늘 정말 중요한 이슈가 있었는가?)
- `핵심 테마`: 오늘 해당되는 테마들 (multi-select)
- `주요 글로벌 딜`: 숫자 (Deals & Transactions Global 섹션의 건수)
- `KRX 이벤트`: `__YES__` 또는 `__NO__`
- `Action Items`: 플레인 텍스트로 요약

### Step 7. Enqueue for Brain Vault ingest

리포트 페이지 완료 후 Brain vault ingest 큐에 JSON 파일 1건 생성.

- 디렉토리: `~/pe-research/ingest-queue/pending/`
- 파일명: `YYYYMMDD-HHMMSS-pe-daily-{notion_page_id}.json` (KST, page_id는 Step 1에서 보관한 값)
- 내용:
  ```json
  {
    "report_type": "pe-daily",
    "notion_page_id": "<Step 1 page_id>",
    "notion_url": "<페이지 URL>",
    "report_date": "YYYY-MM-DD",
    "title": "Daily Research · YYYY-MM-DD",
    "enqueued_at": "<현재 ISO 시각>"
  }
  ```
- Write 도구로 파일 생성. 별도 ingest-worker launchd 잡이 자동으로 Brain vault에 ingest함.

### Step 8. Log completion

Print final page URL and elapsed time. Exit 0 on success, 1 on any failure.

## Important constraints

- Total execution time: aim for 10-15 min, hard cap 20 min
- Max web searches: 25
- Max web fetches: 10
- Copyright: no verbatim quotes >15 words, always paraphrase
- If a section genuinely has no news, write "오늘 특기할 만한 건 없음" — don't fabricate
- Write in Korean 음슴체 (~임/~함/~됨) for body text; English OK in section headers

Execute now.
