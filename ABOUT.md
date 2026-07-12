# pe-research

## 목적
평일 매일 아침 자동 PE/VC 리서치 브리핑 생성.
Notion MCP를 통해 리서치 결과를 Notion에 자동 저장.

## 기술 스택
- Python (shell scripts + Python)
- Anthropic Claude API
- Notion MCP
- launchd (macOS 스케줄러)

## 현재 상태
운영 중. 평일 08:45 자동 실행.

## launchd 스케줄
`com.aerok86.pe-research` — 평일 08:45 daily-research.sh
`com.aerok86.pe-research-genesis` — genesis-research.sh
`com.aerok86.pe-research-ingest` — ingest-worker.sh

## 실행
```bash
./scripts/daily-research.sh
```

## 주의사항
- ANTHROPIC_API_KEY unset 필수 (헤드리스에서 OAuth 강제 사용)
- keychain locked 시 401 오류 → caffeinate + retry 패턴 적용
- macOS sleep/wake 시 네트워크 체크 루프 주의

## 의도 / 다음 단계
- Genesis Capital 리서치 자동화 확장
- 브리핑 품질 개선 (소스 다양화)
