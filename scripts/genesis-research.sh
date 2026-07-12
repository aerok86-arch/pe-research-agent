#!/bin/bash
# =============================================================================
# Genesis PE Daily Research - launchd entry point
# =============================================================================
# 매일 08:45 KST (평일) launchd가 호출. Claude Code headless로 제네시스 PE
# 운용사 + 포트폴리오 + 섹터 + 마켓 리서치 후 Notion에 저장.
#
# 기존 daily-research.sh와 동일한 견고성 패턴 (네트워크 대기 + OAuth 사전체크
# + 재시도) 재사용.
# =============================================================================

set -uo pipefail   # NOTE: -e 빠짐. 단계별 실패를 직접 처리하기 위해.

# --- Config ---
PROJECT_DIR="$HOME/pe-research"
PROMPT_FILE="$PROJECT_DIR/prompts/genesis-research.md"
LOG_DIR="$PROJECT_DIR/logs"
LOG_FILE="$LOG_DIR/genesis-$(date +%Y-%m-%d).log"

# --- Environment setup ---
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
# CRITICAL: unset ANTHROPIC_API_KEY so Claude CLI uses subscription OAuth (higher rate limit)
unset ANTHROPIC_API_KEY

mkdir -p "$LOG_DIR"
cd "$PROJECT_DIR"

# --- Prevent sleep during run (START EARLY — before any wait loop) ---
# 2026-06-08: caffeinate를 가장 먼저 호출. 이전엔 네트워크 체크 후에 호출돼
# wake 직후 sleep 루프에서 재차 sleep으로 빠지는 케이스가 있었음.
caffeinate -d -t 2400 &
CAFFEINATE_PID=$!
trap "kill $CAFFEINATE_PID 2>/dev/null || true" EXIT
sleep 5  # wake 직후 네트워크 스택 안정화 대기

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

# --- Log header ---
{
  echo "================================================================"
  echo "Genesis PE Daily Research Job"
  echo "Start: $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "Project dir: $PROJECT_DIR"
  echo "Prompt: $PROMPT_FILE"
  echo "================================================================"
} | tee -a "$LOG_FILE"

# --- Step 1: 네트워크 준비 대기 (최대 10분) ---
log "[1/3] 네트워크 연결 확인..."
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

# --- Step 2: Claude 인증 사전체크 (최대 3회 재시도) ---
log "[2/3] Claude 인증 확인..."
AUTH_OK=0
for attempt in 1 2 3; do
  AUTH_TEST=$(echo "ping" | claude --print --dangerously-skip-permissions 2>&1)
  AUTH_EXIT=$?
  if [ $AUTH_EXIT -eq 0 ] && ! echo "$AUTH_TEST" | grep -qiE "(authentication_error|invalid.*credentials|401|please.*log.*in)"; then
    log "  인증 OK (응답: ${AUTH_TEST:0:50}...)"
    AUTH_OK=1
    break
  fi
  log "  인증 실패 시도 $attempt/3: ${AUTH_TEST:0:200}"
  if [ "$attempt" -lt 3 ]; then
    log "  3분 대기 후 재시도 (keychain unlock 가능성)"
    sleep 180
  fi
done

if [ $AUTH_OK -eq 0 ]; then
  log "  ERROR: 3회 시도 모두 실패. Claude 구독 OAuth 갱신 필요. 종료."
  log "  해결: 터미널에서 'claude /login' 실행하여 재로그인"
  exit 2
fi

# --- Step 3: 리서치 본 실행 ---
log "[3/3] Genesis 리서치 실행 시작..."
START_TIME=$(date +%s)

if claude \
    --print \
    --dangerously-skip-permissions \
    --mcp-config "$PROJECT_DIR/.mcp.json" \
    --add-dir "$PROJECT_DIR" \
    < "$PROMPT_FILE" \
    >> "$LOG_FILE" 2>&1; then
  END_TIME=$(date +%s)
  ELAPSED=$((END_TIME - START_TIME))
  {
    echo ""
    echo "----------------------------------------------------------------"
    echo "SUCCESS. Elapsed: ${ELAPSED}s"
    echo "End: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "================================================================"
  } | tee -a "$LOG_FILE"
  exit 0
else
  EXIT_CODE=$?
  END_TIME=$(date +%s)
  ELAPSED=$((END_TIME - START_TIME))
  {
    echo ""
    echo "----------------------------------------------------------------"
    echo "FAILURE. Exit code: $EXIT_CODE. Elapsed: ${ELAPSED}s"
    echo "End: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "================================================================"
  } | tee -a "$LOG_FILE"
  exit $EXIT_CODE
fi
