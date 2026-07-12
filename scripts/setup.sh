#!/bin/bash
# =============================================================================
# PE Research - One-time setup
# =============================================================================
# 최초 1회 실행:
#   1) 스크립트 실행 권한 부여
#   2) Claude Code 설치 확인
#   3) Notion integration 토큰 확인
#   4) macOS 자동 깨움 (pmset) 설정
#   5) cron 등록 (confirmation 후)
# =============================================================================

set -euo pipefail

PROJECT_DIR="/Users/aerok86/Library/CloudStorage/OneDrive-공유라이브러리-Onedrive/07_Claude/pe-resarch/pe-research"

echo "================================================================"
echo "PE Research Daily Job - Setup"
echo "Project: $PROJECT_DIR"
echo "================================================================"

# --- 1. Permissions ---
echo ""
echo "[1/5] Setting script permissions..."
chmod +x "$PROJECT_DIR/scripts/daily-research.sh"
chmod +x "$PROJECT_DIR/scripts/test-run.sh"
echo "  OK"

# --- 2. Claude Code check ---
echo ""
echo "[2/5] Checking Claude Code installation..."
if ! command -v claude &> /dev/null; then
  echo "  ERROR: Claude Code not found."
  echo "  Install: https://docs.claude.com/en/docs/claude-code/quickstart"
  exit 1
fi
echo "  OK: $(claude --version 2>/dev/null || echo 'installed')"

# --- 3. Notion token check ---
echo ""
echo "[3/5] Checking Notion integration..."
if grep -q "YOUR_NOTION_INTERNAL_INTEGRATION_SECRET" "$PROJECT_DIR/.mcp.json"; then
  echo "  WARNING: .mcp.json still has placeholder token."
  echo ""
  echo "  To set up Notion integration:"
  echo "  1) Go to https://www.notion.so/profile/integrations"
  echo "  2) Create a new internal integration (name: 'PE Research Agent')"
  echo "  3) Copy the 'Internal Integration Secret'"
  echo "  4) Share the following Notion pages with this integration:"
  echo "     - 📚 Buyout Insight Sources DB"
  echo "     - 📰 Daily Research Reports DB"
  echo "  5) Paste the secret into $PROJECT_DIR/.mcp.json"
  echo "     (replace YOUR_NOTION_INTERNAL_INTEGRATION_SECRET)"
  echo ""
  read -p "  Notion setup complete? (y/N): " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "  Setup aborted. Complete Notion setup and re-run this script."
    exit 1
  fi
fi
echo "  OK"

# --- 4. pmset (wake Mac from sleep before job) ---
echo ""
echo "[4/5] Configuring macOS auto-wake (pmset)..."
echo "  This requires sudo. The Mac will wake at 08:40 Mon-Fri"
echo "  to ensure the 08:45 cron job runs."
echo ""
read -p "  Configure auto-wake? (y/N): " wake_confirm
if [[ "$wake_confirm" == "y" || "$wake_confirm" == "Y" ]]; then
  sudo pmset repeat wake MTWRF 08:40:00
  echo "  OK: Mac will wake at 08:40 Mon-Fri"
  echo "  (check with: pmset -g sched)"
else
  echo "  SKIPPED. You'll need to keep the Mac awake at 08:45 manually."
fi

# --- 5. cron registration ---
echo ""
echo "[5/5] Registering cron job..."
echo "  The job will run at 08:45 Mon-Fri KST."
echo ""

CRON_LINE="45 8 * * 1-5 \"$PROJECT_DIR/scripts/daily-research.sh\""
echo "  cron line to add:"
echo "    $CRON_LINE"
echo ""
read -p "  Register now? (y/N): " cron_confirm

if [[ "$cron_confirm" == "y" || "$cron_confirm" == "Y" ]]; then
  # Check if already registered
  if crontab -l 2>/dev/null | grep -q "pe-resarch/pe-research/scripts/daily-research.sh"; then
    echo "  WARNING: cron entry for pe-research already exists. Skipping."
    echo "  Current crontab:"
    crontab -l | grep pe-research
  else
    # Append to existing crontab
    (crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -
    echo "  OK: Registered"
    echo "  Verify: crontab -l"
  fi
else
  echo "  SKIPPED. Register manually with:"
  echo "    (crontab -l; echo '$CRON_LINE') | crontab -"
fi

# --- Notion permission note ---
echo ""
echo "================================================================"
echo "IMPORTANT: macOS may prompt for these permissions on first run:"
echo "  - cron needs 'Full Disk Access' (System Settings > Privacy & Security)"
echo "  - Add /usr/sbin/cron to Full Disk Access list"
echo "  - Also add Terminal/iTerm to Full Disk Access (OneDrive path access)"
echo ""
echo "Test manually first:"
echo "  bash \"$PROJECT_DIR/scripts/test-run.sh\""
echo ""
echo "Setup complete."
echo "================================================================"
