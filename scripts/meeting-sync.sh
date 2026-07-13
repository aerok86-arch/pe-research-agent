#!/bin/bash
# =============================================================================
# Meeting Notes Sync (Notion 회의록 -> Brain Vault)
# =============================================================================
# 매일 1회 fire. checkpoint(state/meeting-sync-state.json) 이후 신규 회의록을
# 조회하여 업무(PE) 관련 항목만 vault에 ingest. 개인 항목은 자동 제외.
#
# 견고성 패턴은 ingest-worker.sh와 동일 (2026-06-08 검증됨):
# - caffeinate 최상단 호출
# - 네트워크 사전체크 10회/60s
# - Claude OAuth 사전체크 3회/3분
# - iCloud vault 쓰기 가능성 검증
# =============================================================================

set -uo pipefail

PROJECT_DIR="$HOME/pe-research"
PROMPT_FILE="$PROJECT_DIR/prompts/meeting-sync.md"
VAULT_DIR="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Brain"
STATE_DIR="$PROJECT_DIR/state"
LOG_DIR="$PROJECT_DIR/logs"
LOG_FILE="$LOG_DIR/meeting-sync-$(date +%Y-%m-%d).log"

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
unset ANTHROPIC_API_KEY

mkdir -p "$LOG_DIR" "$STATE_DIR"
cd "$PROJECT_DIR"

caffeinate -d -t 2400 &
CAFFEINATE_PID=$!
trap "kill $CAFFEINATE_PID 2>/dev/null || true" EXIT
sleep 5

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

{
  echo "================================================================"
  echo "Meeting Notes Sync"
  echo "Start: $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "Vault: $VAULT_DIR"
  echo "================================================================"
} | tee -a "$LOG_FILE"

log "[1/4] 네트워크 연결 확인..."
for i in 1 2 3 4 5 6 7 8 9 10; do
  if curl -s --max-time 5 -o /dev/null https://api.anthropic.com 2>&1; then
    log "  네트워크 OK"
    break
  fi
  if [ "$i" = 10 ]; then
    log "  ERROR: 10분 대기 후에도 네트워크 미연결. 종료."
    exit 1
  fi
  log "  네트워크 미준비 ($i/10) — 60초 후 재시도"
  sleep 60
done

log "[2/4] iCloud vault 접근 확인..."
if [ ! -d "$VAULT_DIR" ]; then
  log "  ERROR: vault 경로 미존재. 종료."
  exit 2
fi
TEST_FILE="$VAULT_DIR/.meeting-sync-write-test-$$"
if ! touch "$TEST_FILE" 2>&1; then
  log "  ERROR: vault 쓰기 실패(권한). 종료."
  exit 3
fi
rm -f "$TEST_FILE"
log "  vault 쓰기 OK"

log "[3/4] Claude 인증 확인..."
AUTH_OK=0
for attempt in 1 2 3; do
  AUTH_TEST=$(echo "ping" | claude --print --dangerously-skip-permissions 2>&1)
  AUTH_EXIT=$?
  if [ $AUTH_EXIT -eq 0 ] && ! echo "$AUTH_TEST" | grep -qiE "(authentication_error|invalid.*credentials|401|please.*log.*in)"; then
    log "  인증 OK"
    AUTH_OK=1
    break
  fi
  log "  인증 실패 시도 $attempt/3"
  if [ "$attempt" -lt 3 ]; then
    sleep 180
  fi
done

if [ $AUTH_OK -eq 0 ]; then
  log "  ERROR: OAuth 인증 실패. 종료."
  exit 4
fi

log "[4/4] Claude 헤드리스 실행..."
RUN_LOG="$LOG_DIR/meeting-sync-item-$(date +%Y%m%d-%H%M%S).log"
START_TIME=$(date +%s)

if claude \
    --print \
    --dangerously-skip-permissions \
    --mcp-config "$PROJECT_DIR/.mcp.json" \
    --add-dir "$PROJECT_DIR" \
    --add-dir "$VAULT_DIR" \
    < "$PROMPT_FILE" \
    > "$RUN_LOG" 2>&1; then
  ELAPSED=$(($(date +%s) - START_TIME))
  if grep -q "status=success" "$RUN_LOG" || grep -q "status=no_new_items" "$RUN_LOG"; then
    log "  ✓ 성공 (elapsed ${ELAPSED}s) — 로그: $RUN_LOG"
    grep -A8 "===SYNC_RESULT===" "$RUN_LOG" | tee -a "$LOG_FILE" || true
    EXIT_CODE=0
  else
    log "  ✗ 완료 마커 누락 — 로그 확인 필요: $RUN_LOG"
    EXIT_CODE=1
  fi
else
  EXIT_CODE=$?
  log "  ✗ Claude exit $EXIT_CODE — 로그: $RUN_LOG"
fi

{
  echo ""
  echo "----------------------------------------------------------------"
  echo "End: $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "================================================================"
} | tee -a "$LOG_FILE"

exit $EXIT_CODE
