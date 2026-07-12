#!/bin/bash
# =============================================================================
# Brain Vault Ingest Worker
# =============================================================================
# pending 큐를 스캔하여 각 항목을 Brain vault에 ingest.
# 평일 09:30/14:00/21:00 정기 fire + RunAtLoad=true로 부팅 직후 백로그 소화.
#
# 견고성 패턴(2026-06-08):
# - caffeinate를 가장 먼저 호출
# - 네트워크 사전체크 10회/60s (총 10분)
# - Claude OAuth 사전체크 3회/3분 (keychain unlock 대기)
# - iCloud vault 접근 가능성 검증
# - 큐 처리 시 idempotency 보장 (vault 측에서 중복 체크)
# =============================================================================

set -uo pipefail

# --- Config ---
PROJECT_DIR="$HOME/pe-research"
QUEUE_DIR="$PROJECT_DIR/ingest-queue"
PENDING_DIR="$QUEUE_DIR/pending"
DONE_DIR="$QUEUE_DIR/done"
FAILED_DIR="$QUEUE_DIR/failed"
PROMPT_TEMPLATE="$PROJECT_DIR/prompts/ingest-daily.md"
VAULT_DIR="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Brain"
LOG_DIR="$PROJECT_DIR/logs"
LOG_FILE="$LOG_DIR/ingest-$(date +%Y-%m-%d).log"

# --- Environment setup ---
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
# CRITICAL: unset ANTHROPIC_API_KEY so Claude CLI uses subscription OAuth
unset ANTHROPIC_API_KEY

mkdir -p "$LOG_DIR" "$PENDING_DIR" "$DONE_DIR" "$FAILED_DIR"
cd "$PROJECT_DIR"

# --- Prevent sleep during run (START EARLY) ---
caffeinate -d -t 2400 &
CAFFEINATE_PID=$!
trap "kill $CAFFEINATE_PID 2>/dev/null || true" EXIT
sleep 5  # wake 직후 안정화

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

{
  echo "================================================================"
  echo "Brain Vault Ingest Worker"
  echo "Start: $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "Queue: $PENDING_DIR"
  echo "Vault: $VAULT_DIR"
  echo "================================================================"
} | tee -a "$LOG_FILE"

# --- Quick exit: queue empty ---
PENDING_FILES=("$PENDING_DIR"/*.json)
if [ ! -e "${PENDING_FILES[0]}" ]; then
  log "큐 비어있음. 종료."
  exit 0
fi
PENDING_COUNT=${#PENDING_FILES[@]}
log "처리 대기: $PENDING_COUNT 건"

# --- Network precheck (10 tries / 60s = max 10min) ---
log "[1/4] 네트워크 연결 확인..."
for i in 1 2 3 4 5 6 7 8 9 10; do
  if curl -s --max-time 5 -o /dev/null https://api.anthropic.com 2>&1; then
    log "  네트워크 OK"
    break
  fi
  if [ "$i" = 10 ]; then
    log "  ERROR: 10분 대기 후에도 네트워크 미연결. 종료(큐 보존)."
    exit 1
  fi
  log "  네트워크 미준비 ($i/10) — 60초 후 재시도"
  sleep 60
done

# --- Vault access check ---
log "[2/4] iCloud vault 접근 확인..."
if [ ! -d "$VAULT_DIR" ]; then
  log "  ERROR: vault 경로 미존재. 종료(큐 보존)."
  exit 2
fi
TEST_FILE="$VAULT_DIR/.ingest-worker-write-test-$$"
if ! touch "$TEST_FILE" 2>&1; then
  log "  ERROR: vault 쓰기 실패(권한). 종료(큐 보존)."
  exit 3
fi
rm -f "$TEST_FILE"
log "  vault 쓰기 OK"

# --- Claude OAuth precheck (3 tries / 3min) ---
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
  log "  ERROR: OAuth 인증 실패. 종료(큐 보존)."
  exit 4
fi

# --- Process queue ---
log "[4/4] 큐 처리 시작..."
PROCESSED=0
SUCCESS=0
FAILED=0

for QUEUE_FILE in "$PENDING_DIR"/*.json; do
  [ -e "$QUEUE_FILE" ] || continue
  PROCESSED=$((PROCESSED + 1))
  BASENAME=$(basename "$QUEUE_FILE")
  log "  [$PROCESSED/$PENDING_COUNT] $BASENAME 처리 중..."

  ITEM_LOG="$LOG_DIR/ingest-item-$(date +%Y%m%d-%H%M%S)-$BASENAME.log"
  START_TIME=$(date +%s)

  # Build full prompt (template + queue JSON appended)
  COMBINED_PROMPT=$(mktemp)
  trap "rm -f $COMBINED_PROMPT" RETURN
  {
    cat "$PROMPT_TEMPLATE"
    echo ""
    echo '```json'
    cat "$QUEUE_FILE"
    echo '```'
  } > "$COMBINED_PROMPT"

  # Run Claude headless with vault dir added
  if claude \
      --print \
      --dangerously-skip-permissions \
      --mcp-config "$PROJECT_DIR/.mcp.json" \
      --add-dir "$PROJECT_DIR" \
      --add-dir "$VAULT_DIR" \
      < "$COMBINED_PROMPT" \
      > "$ITEM_LOG" 2>&1; then
    # Check INGEST_RESULT marker
    if grep -q "status=success" "$ITEM_LOG" || grep -q "status=already_ingested" "$ITEM_LOG"; then
      mv "$QUEUE_FILE" "$DONE_DIR/"
      SUCCESS=$((SUCCESS + 1))
      ELAPSED=$(($(date +%s) - START_TIME))
      log "    ✓ 성공 (elapsed ${ELAPSED}s) → done/"
    else
      mv "$QUEUE_FILE" "$FAILED_DIR/"
      FAILED=$((FAILED + 1))
      log "    ✗ 마커 누락 → failed/ (로그: $ITEM_LOG)"
    fi
  else
    EXIT_CODE=$?
    mv "$QUEUE_FILE" "$FAILED_DIR/"
    FAILED=$((FAILED + 1))
    log "    ✗ Claude exit $EXIT_CODE → failed/ (로그: $ITEM_LOG)"
  fi

  rm -f "$COMBINED_PROMPT"
done

{
  echo ""
  echo "----------------------------------------------------------------"
  echo "처리 완료: $PROCESSED건 (성공 $SUCCESS / 실패 $FAILED)"
  echo "End: $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "================================================================"
} | tee -a "$LOG_FILE"

if [ $FAILED -gt 0 ]; then
  exit 1
fi
exit 0
