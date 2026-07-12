#!/bin/bash
# =============================================================================
# PE Research - Manual test run
# =============================================================================
# cron 등록 없이 수동으로 리서치 잡을 실행해 정상 작동 확인.
# 결과는 logs/test-YYYYMMDD-HHMM.log 에 저장되고 stdout에도 출력됨.
# =============================================================================

set -euo pipefail

PROJECT_DIR="$HOME/pe-research"
PROMPT_FILE="$PROJECT_DIR/prompts/daily-research.md"
LOG_FILE="$PROJECT_DIR/logs/test-$(date +%Y%m%d-%H%M).log"

mkdir -p "$PROJECT_DIR/logs"
cd "$PROJECT_DIR"

# CRITICAL: unset ANTHROPIC_API_KEY so Claude CLI uses subscription OAuth (higher rate limit)
unset ANTHROPIC_API_KEY

echo "================================================================"
echo "TEST RUN"
echo "Log: $LOG_FILE"
echo "Project: $PROJECT_DIR"
echo "================================================================"

START_TIME=$(date +%s)

claude \
  --print \
  --dangerously-skip-permissions \
  --mcp-config "$PROJECT_DIR/.mcp.json" \
  --add-dir "$PROJECT_DIR" \
  < "$PROMPT_FILE" 2>&1 | tee "$LOG_FILE"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "================================================================"
echo "Test complete. Elapsed: ${ELAPSED}s"
echo "Log saved: $LOG_FILE"
echo "================================================================"
