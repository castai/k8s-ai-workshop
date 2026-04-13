#!/bin/bash
# Workshop bootstrap — single entry point for kimchi + OpenCode setup
set -e

KIMCHI_VERSION="v0.1.30"
CASTAI_API_KEY="${KIMCHI_API_KEY:-${CASTAI_API_KEY:-}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

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
if ! command -v kimchi &>/dev/null || [ "$(kimchi version 2>/dev/null)" != "${KIMCHI_VERSION}" ]; then
  step "Install kimchi CLI (${KIMCHI_VERSION})" bash -c '
    OS=$(uname -s | tr "[:upper:]" "[:lower:]")
    ARCH=$(uname -m)
    case "$ARCH" in x86_64) ARCH="amd64" ;; aarch64|arm64) ARCH="arm64" ;; esac
    curl -fsSL "https://github.com/castai/kimchi/releases/download/'"${KIMCHI_VERSION}"'/kimchi_${OS}_${ARCH}.tar.gz" \
      | tar -xzf - -C /tmp
    chmod +x /tmp/kimchi
    sudo mv /tmp/kimchi /usr/local/bin/kimchi
  '
  state_mark "kimchi-installed"
else
  printf "  ${GREEN}[✓]${NC} Install kimchi CLI (${KIMCHI_VERSION}) ${DIM}(cached)${NC}\n"
fi

# --- Stage 2: Update shell profile -----------------------------------------
if ! state_done "shell-profile"; then
  step "Update shell profile" bash -c '
    if ! grep -q "CASTAI_API_KEY" ~/.bashrc 2>/dev/null; then
      cat >> ~/.bashrc << PROFILE
export CASTAI_API_KEY="'"${CASTAI_API_KEY}"'"
export OPENCODE_ENABLE_TELEMETRY=1
export OPENCODE_OTLP_ENDPOINT="https://api.cast.ai/ai-optimizer/v1beta/logs:ingest"
export OPENCODE_OTLP_METRICS_ENDPOINT="https://api.cast.ai/ai-optimizer/v1beta/metrics:ingest"
alias opencode="kimchi opencode"
PROFILE
    fi
  '
  state_mark "shell-profile"
else
  printf "  ${GREEN}[✓]${NC} Update shell profile ${DIM}(cached)${NC}\n"
fi

# --- Stage 3: Install OpenCode ---------------------------------------------
if ! state_done "opencode-installed"; then
  step "Install OpenCode" "$SCRIPT_DIR/install-opencode.sh"
  state_mark "opencode-installed"
else
  printf "  ${GREEN}[✓]${NC} Install OpenCode ${DIM}(cached)${NC}\n"
fi

# --- Stage 4: Configure OpenCode MCP + skills ------------------------------
if ! state_done "opencode-configured"; then
  step "Configure OpenCode (MCP + skills)" "$SCRIPT_DIR/setup-opencode.sh"
  state_mark "opencode-configured"
else
  printf "  ${GREEN}[✓]${NC} Configure OpenCode (MCP + skills) ${DIM}(cached)${NC}\n"
fi

# --- Stage 5: Configure kimchi (after OpenCode to avoid overwritten values)
if ! state_done "kimchi-configured"; then
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
  state_mark "kimchi-configured"
else
  printf "  ${GREEN}[✓]${NC} Configure kimchi ${DIM}(cached)${NC}\n"
fi

# --- Source bashrc so env vars and alias are available in the current shell --
source ~/.bashrc 2>/dev/null || true

# --- Done ------------------------------------------------------------------
echo ""
echo -e "  ${GREEN}${BOLD}Setup complete!${NC}"
echo ""
echo -e "  Run ${BLUE}opencode${NC} to start coding."
echo ""
