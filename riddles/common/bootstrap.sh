#!/bin/bash
# Workshop bootstrap — single entry point for kimchi + OpenCode setup
set -e

KIMCHI_VERSION="v0.1.27"
CASTAI_API_KEY="${KIMCHI_API_KEY:-${CASTAI_API_KEY:-}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Colors ---------------------------------------------------------------
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# --- Step runner -----------------------------------------------------------
# Runs a command, captures output. Shows [✓] on success, [✗] + output on failure.
step() {
  local label="$1"; shift
  printf "  [ ] %s" "$label"
  local output exit_code=0
  output=$("$@" 2>&1) || exit_code=$?
  if [ $exit_code -eq 0 ]; then
    printf "\r  ${GREEN}[✓]${NC} %s\n" "$label"
  else
    printf "\r  ${RED}[✗]${NC} %s\n" "$label"
    if [ -n "$output" ]; then
      echo "$output" | sed 's/^/      /'
    fi
    exit 1
  fi
}

# --- Banner ----------------------------------------------------------------
echo ""
echo -e "  ${BOLD}Kimchi CLI Bootstrap${NC} ${DIM}${KIMCHI_VERSION}${NC}"
echo ""

# --- Validate API key ------------------------------------------------------
if [ -z "$CASTAI_API_KEY" ]; then
  printf "  ${RED}[✗]${NC} KIMCHI_API_KEY is not set\n"
  echo ""
  echo -e "      Usage: ${BLUE}KIMCHI_API_KEY=<your-key> $0${NC}"
  echo -e "             ${DIM}(CASTAI_API_KEY also accepted)${NC}"
  echo ""
  exit 1
fi
printf "  ${GREEN}[✓]${NC} API key provided\n"

# --- Stage 1: Install kimchi CLI -------------------------------------------
step "Install kimchi CLI (${KIMCHI_VERSION})" bash -c '
  OS=$(uname -s | tr "[:upper:]" "[:lower:]")
  ARCH=$(uname -m)
  case "$ARCH" in x86_64) ARCH="amd64" ;; aarch64|arm64) ARCH="arm64" ;; esac
  curl -fsSL "https://github.com/castai/kimchi/releases/download/'"${KIMCHI_VERSION}"'/kimchi_${OS}_${ARCH}.tar.gz" \
    | tar -xzf - -C /tmp
  chmod +x /tmp/kimchi
  mv /tmp/kimchi /usr/local/bin/kimchi
'

# --- Stage 2: Configure kimchi ---------------------------------------------
step "Configure kimchi" bash -c '
  mkdir -p ~/.config/kimchi
  cat > ~/.config/kimchi/config.json << CONF
{
  "api_key": "'"${CASTAI_API_KEY}"'",
  "mode": "inject",
  "selected_tools": ["opencode"],
  "scope": "global",
  "telemetry_enabled": true,
  "telemetry_notice_shown": true
}
CONF
  chmod 600 ~/.config/kimchi/config.json
'

# --- Stage 3: Update shell profile -----------------------------------------
step "Update shell profile" bash -c '
  # Only append if not already present
  if ! grep -q "CASTAI_API_KEY" ~/.bashrc 2>/dev/null; then
    cat >> ~/.bashrc << PROFILE
export CASTAI_API_KEY="'"${CASTAI_API_KEY}"'"
alias opencode="kimchi opencode"
PROFILE
  fi
'

# --- Stage 4: Install OpenCode ---------------------------------------------
step "Install OpenCode" "$SCRIPT_DIR/install-opencode.sh"

# --- Stage 5: Configure OpenCode MCP + skills ------------------------------
step "Configure OpenCode (MCP + skills)" env CASTAI_API_KEY="$CASTAI_API_KEY" \
  "$SCRIPT_DIR/setup-opencode.sh" --with-castai

# --- Done ------------------------------------------------------------------
echo ""
echo -e "  ${GREEN}${BOLD}Setup complete!${NC}"
echo ""
echo -e "  Run ${BLUE}opencode${NC} to start coding."
echo ""
