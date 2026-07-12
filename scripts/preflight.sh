#!/bin/bash
# =============================================================================
# PE Research - Preflight check
# =============================================================================
# 테스트 실행 전에 환경이 제대로 갖춰졌는지 빠르게 점검.
# - claude CLI
# - .mcp.json 구문
# - Notion 토큰 유효성
# - 소스/리포트 DB 접근 가능성
# - 경로 및 권한
# =============================================================================

set -uo pipefail

PROJECT_DIR="$HOME/pe-research"
SOURCES_DB="a54169bc-4802-4ec8-89f1-9e56cbf9fee4"
REPORTS_DB="690d6d64-46dc-4f4f-a970-0543377139c2"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; FAIL=1; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }

FAIL=0

echo "================================================================"
echo "PE Research - Preflight Check"
echo "================================================================"

# 1. Project directory
echo ""
echo "[1] Project directory"
if [ -d "$PROJECT_DIR" ]; then
  pass "exists: $PROJECT_DIR"
else
  fail "NOT FOUND: $PROJECT_DIR"
  exit 1
fi

# 2. Required files
echo ""
echo "[2] Required files"
for f in CLAUDE.md .mcp.json prompts/daily-research.md scripts/daily-research.sh scripts/test-run.sh; do
  if [ -f "$PROJECT_DIR/$f" ]; then
    pass "$f"
  else
    fail "MISSING: $f"
  fi
done

# 3. Script executability
echo ""
echo "[3] Script permissions"
for s in daily-research.sh test-run.sh setup.sh preflight.sh; do
  if [ -x "$PROJECT_DIR/scripts/$s" ]; then
    pass "$s (executable)"
  else
    warn "$s not executable — fixing with chmod +x"
    chmod +x "$PROJECT_DIR/scripts/$s" 2>/dev/null || fail "could not chmod $s"
  fi
done

# 4. Claude CLI
echo ""
echo "[4] Claude Code CLI"
if command -v claude &> /dev/null; then
  pass "installed: $(claude --version 2>/dev/null)"
else
  fail "claude not in PATH"
fi

# 5. .mcp.json valid JSON
echo ""
echo "[5] .mcp.json JSON validity"
if python3 -m json.tool "$PROJECT_DIR/.mcp.json" > /dev/null 2>&1; then
  pass "valid JSON"
else
  fail "invalid JSON — check escaping"
fi

# 6. Extract Notion token
echo ""
echo "[6] Notion token extraction"
TOKEN=$(python3 -c "
import json
with open('$PROJECT_DIR/.mcp.json') as f:
    cfg = json.load(f)
hdrs_str = cfg['mcpServers']['notion']['env']['OPENAPI_MCP_HEADERS']
hdrs = json.loads(hdrs_str)
auth = hdrs.get('Authorization','')
print(auth.replace('Bearer ','').strip())
" 2>&1)
if [ -n "$TOKEN" ] && [[ "$TOKEN" == ntn_* || "$TOKEN" == secret_* ]]; then
  pass "token extracted (${TOKEN:0:8}...${TOKEN: -4})"
else
  fail "could not extract valid token: $TOKEN"
  exit 1
fi

# 7. Notion auth check
echo ""
echo "[7] Notion API authentication"
USER_RESP=$(curl -s -H "Authorization: Bearer $TOKEN" -H "Notion-Version: 2022-06-28" https://api.notion.com/v1/users/me)
USER_NAME=$(echo "$USER_RESP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('name','?'))" 2>&1)
if [[ "$USER_NAME" != "?" && "$USER_NAME" != *"error"* ]]; then
  pass "authenticated as: $USER_NAME"
else
  fail "auth failed: $USER_RESP"
fi

# 8. Source DB access
echo ""
echo "[8] Notion database access"
for DB_INFO in "Sources:$SOURCES_DB" "Reports:$REPORTS_DB"; do
  LABEL="${DB_INFO%%:*}"
  DB_ID="${DB_INFO##*:}"
  DB_RESP=$(curl -s -H "Authorization: Bearer $TOKEN" -H "Notion-Version: 2022-06-28" "https://api.notion.com/v1/databases/$DB_ID")
  OBJ=$(echo "$DB_RESP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('object','error'))" 2>&1)
  if [ "$OBJ" = "database" ]; then
    pass "$LABEL DB accessible"
  else
    fail "$LABEL DB NOT accessible — share integration with this DB"
  fi
done

# 9. cron status
echo ""
echo "[9] cron registration"
if crontab -l 2>/dev/null | grep -q "pe-resarch/pe-research/scripts/daily-research.sh"; then
  pass "cron job registered"
  crontab -l | grep pe-resarch | sed 's/^/    /'
else
  warn "not registered yet — run setup.sh to register"
fi

# 10. pmset wake schedule
echo ""
echo "[10] macOS wake schedule (pmset)"
if pmset -g sched 2>/dev/null | grep -q "wake"; then
  pass "wake schedule set"
  pmset -g sched | grep -i wake | sed 's/^/    /'
else
  warn "no wake schedule — run setup.sh with sudo to set"
fi

# Summary
echo ""
echo "================================================================"
if [ $FAIL -eq 0 ]; then
  echo -e "${GREEN}ALL CHECKS PASSED${NC} — ready to run test-run.sh"
else
  echo -e "${RED}SOME CHECKS FAILED${NC} — fix above issues before testing"
fi
echo "================================================================"
exit $FAIL
