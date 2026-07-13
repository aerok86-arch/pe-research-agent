# PE Research Agent

PE/Buyout 업계 일일 리서치를 자동화하는 Claude Code 기반 에이전트.  
매일 평일 08:45 KST에 스케줄러가 자동 실행 → 10개 섹션 리포트를 Notion에 저장.

---

## 개요

| 항목 | 내용 |
|---|---|
| **에이전트** | Claude Code (headless, `--print --dangerously-skip-permissions`) |
| **Notion MCP** | `@notionhq/notion-mcp-server` |
| **실행 주기** | 평일 08:45 KST |
| **출력** | Notion "📰 Daily Research Reports" DB |
| **소스 커버리지** | Tier 1 글로벌(PEI, Buyouts, FT DD 등) + Korea PE(한경, 더벨 등) |

### 실행 흐름

```
[08:45] Scheduler 트리거
   ↓
scripts/daily-research.sh (macOS) 또는 scripts/windows/daily-research.ps1 (Windows)
   ↓ 네트워크 대기 → Claude OAuth 인증 확인
   ↓
Claude Code headless (prompts/daily-research.md 실행)
   ↓
1. Notion에 "진행 중" 페이지 생성
2. Tier 1 소스 웹 검색 (8~10건)
3. Korea PE 언론 검색 (3~5건)
4. Operational insights 검색 (2~3건)
5. 10개 섹션 리포트 작성
6. Notion 페이지 업데이트 → 상태: 완료
   ↓
ingest-queue/pending/에 JSON 저장
   ↓
[09:30/14:00/21:00] Ingest Worker → Brain Vault(Obsidian)에 흡수
```

---

## 프로젝트 구조

```
pe-research/
├── prompts/
│   ├── daily-research.md      # PE 일일 리서치 Claude 프롬프트
│   ├── genesis-research.md    # Genesis PE 특화 리서치 프롬프트
│   └── ingest-daily.md        # Brain Vault ingest 프롬프트
├── scripts/
│   ├── daily-research.sh      # macOS 실행 스크립트 (launchd)
│   ├── genesis-research.sh    # macOS Genesis 스크립트
│   ├── ingest-worker.sh       # macOS Ingest Worker 스크립트
│   ├── meeting-sync.sh        # macOS 회의록 sync 스크립트 (수동 실행용 — 스케줄러는 Windows 전용, 아래 참고)
│   ├── preflight.sh           # 환경 사전 점검
│   ├── test-run.sh            # 수동 테스트 실행
│   └── windows/
│       ├── daily-research.ps1 # Windows PowerShell 스크립트
│       ├── genesis-research.ps1
│       ├── ingest-worker.ps1
│       └── meeting-sync.ps1   # 회의록 sync (스케줄러는 Windows에서만 등록 — 아래 참고)
├── scheduler/
│   ├── macos/                 # launchd plist 파일
│   └── windows/               # Task Scheduler XML 파일
│       ├── daily-research.xml
│       ├── genesis-research.xml
│       ├── ingest-worker.xml
│       └── meeting-sync.xml
│       └── ingest-worker.xml
├── ingest-queue/
│   ├── pending/               # 처리 대기 JSON
│   ├── done/                  # 완료 JSON
│   └── failed/                # 실패 JSON
├── logs/                      # 실행 로그 (gitignore)
├── .mcp.json                  # Notion MCP 설정 (gitignore — 직접 생성 필요)
├── .mcp.json.example          # 설정 템플릿
├── CLAUDE.md                  # Claude 에이전트 컨텍스트 (Notion DB ID 등)
└── AGENTS.md                  # 에이전트 역할 정의
```

---

## 사전 요구사항

| 항목 | macOS | Windows |
|---|---|---|
| Claude Code CLI | `npm install -g @anthropic-ai/claude-code` | 동일 |
| Node.js | 18+ | 18+ |
| Claude 구독 | Max 또는 Pro (OAuth 사용) | 동일 |
| Notion Integration | 필요 | 동일 |
| curl | 기본 내장 | PowerShell Invoke-WebRequest 사용 |

---

## 설치 방법

### 1. 레포 클론

**macOS:**
```bash
git clone https://github.com/aerok86-arch/pe-research-agent.git ~/pe-research
cd ~/pe-research
```

**Windows (PowerShell):**
```powershell
git clone https://github.com/aerok86-arch/pe-research-agent.git "$env:USERPROFILE\pe-research"
cd "$env:USERPROFILE\pe-research"
```

### 2. Notion 연동 설정

1. [Notion Integrations](https://www.notion.so/my-integrations)에서 내부 통합 생성
2. "📚 Buyout Insight Sources" DB와 "📰 Daily Research Reports" DB에 통합 연결
3. `.mcp.json` 파일 생성:

```bash
cp .mcp.json.example .mcp.json
# .mcp.json에서 YOUR_NOTION_TOKEN을 실제 토큰으로 교체
```

`.mcp.json` 형식:
```json
{
  "mcpServers": {
    "notion": {
      "command": "npx",
      "args": ["-y", "@notionhq/notion-mcp-server"],
      "env": {
        "OPENAPI_MCP_HEADERS": "{\"Authorization\":\"Bearer ntn_YOUR_TOKEN\",\"Notion-Version\":\"2022-06-28\"}"
      }
    }
  }
}
```

### 3. Claude 로그인

```bash
claude login
```

> **중요:** `ANTHROPIC_API_KEY` 환경변수가 설정되어 있으면 스크립트가 자동으로 unset함 (OAuth 강제).  
> API Key 방식은 rate limit이 낮으므로 반드시 구독 OAuth 사용.

### 4. 스케줄러 등록

#### macOS (launchd)

```bash
cp scheduler/macos/*.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.aerok86.pe-research.plist
launchctl load ~/Library/LaunchAgents/com.aerok86.pe-research-genesis.plist
launchctl load ~/Library/LaunchAgents/com.aerok86.pe-research-ingest.plist

# 상태 확인
launchctl list | grep pe-research
```

#### Windows (Task Scheduler)

PowerShell (관리자 권한):
```powershell
schtasks /Create /XML "$env:USERPROFILE\pe-research\scheduler\windows\daily-research.xml" /TN "PE\DailyResearch" /F
schtasks /Create /XML "$env:USERPROFILE\pe-research\scheduler\windows\genesis-research.xml" /TN "PE\GenesisResearch" /F
schtasks /Create /XML "$env:USERPROFILE\pe-research\scheduler\windows\ingest-worker.xml" /TN "PE\IngestWorker" /F
schtasks /Create /XML "$env:USERPROFILE\pe-research\scheduler\windows\meeting-sync.xml" /TN "PE\MeetingSync" /F

# 상태 확인
schtasks /Query /TN "PE\DailyResearch" /FO LIST
```

> **Meeting Sync는 Windows 전용 스케줄.** 맥북은 휴대용이라 꺼져있거나 잠들어 있는 시간이 많고, Windows PC는 항상 켜져있는 고정 데스크탑이라 여기서만 스케줄 등록함 (2026-07-13 결정). macOS 쪽엔 `scripts/meeting-sync.sh`가 남아있지만 launchd 등록은 하지 않음 — 필요 시 수동 실행(`bash ~/pe-research/scripts/meeting-sync.sh`)만 가능. 같은 vault(iCloud)에 두 기기가 동시에 쓰면 sync 충돌 위험이 있어 실행 주체를 하나로 고정.

또는 `작업 스케줄러` UI → `작업 가져오기`로 XML 파일 직접 임포트.

> **Windows 주의:** PowerShell 실행 정책 허용 필요:
> ```powershell
> Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
> ```

### 5. Obsidian Vault 경로 설정 (Ingest Worker만 해당)

**macOS** — `scripts/ingest-worker.sh`의 `VAULT_DIR` 변수 확인:
```bash
VAULT_DIR="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Brain"
```

**Windows** — `scripts/windows/ingest-worker.ps1`와 `scripts/windows/meeting-sync.ps1` **둘 다** `$VaultDir` 변수를 실제 경로(iCloud/Obsidian vault가 Windows에 동기화되는 경로)로 수정:
```powershell
$VaultDir = "$env:USERPROFILE\Documents\Brain"
```

---

## 수동 실행

**macOS:**
```bash
bash ~/pe-research/scripts/daily-research.sh
```

**Windows:**
```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\pe-research\scripts\windows\daily-research.ps1"
```

---

## 로그 확인

**macOS:**
```bash
tail -f ~/pe-research/logs/$(date +%Y-%m-%d).log
```

**Windows:**
```powershell
Get-Content "$env:USERPROFILE\pe-research\logs\$(Get-Date -Format 'yyyy-MM-dd').log" -Wait
```

---

## Notion DB 구조

`CLAUDE.md`에 DB ID, 스키마, 리서치 워크플로가 상세 정의되어 있음.

### 리포트 섹션 구조
1. ⚡️ TL;DR (3줄 요약)
2. 🌏 Macro & Market Snapshot
3. 💼 Deals & Transactions (Global + Korea)
4. 💰 Fundraising
5. 🛠 Value Creation / Operational Insights
6. 📜 Regulatory & Policy
7. 🎙 Notable Reads & Listens
8. 🇰🇷 Korea Focus
9. ✅ Action Items
10. 📎 Source Coverage

---

## 자주 발생하는 문제

### macOS — 08:45에 잠들어 있어 실행 안 됨
`StartCalendarInterval`은 잠든 상태에서 missed fire를 복구하지 않음.
```bash
sudo pmset repeat wakeorpoweron MTWRF 08:40:00
```

### Claude 인증 오류 (exit code 2)
```bash
claude login
```

### Windows — PowerShell 실행 정책 오류
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Notion API 403
DB 페이지 `...` → `연결` → Integration 추가 후 재시도.

---

## 라이선스

Private — 개인용 자동화 도구
