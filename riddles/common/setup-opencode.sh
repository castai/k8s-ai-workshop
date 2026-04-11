#!/usr/bin/env bash

# Configure OpenCode MCP servers and skills
# Can be run standalone or called from kimchi-cli-bootstrap.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse flags
WITH_CASTAI=false
for arg in "$@"; do
    case "$arg" in
        --with-castai) WITH_CASTAI=true ;;
    esac
done

# Get participant name and register in the Loveable dashboard (skipped when --with-castai is passed).
if [ "$WITH_CASTAI" = false ]; then
    read -p "Enter your name: " NAME

    CLUSTER_UID=$(kubectl get namespace kube-system -o jsonpath='{.metadata.uid}')

    RESPONSE=$(curl -s -X POST 'https://hsnxzbyedgzepraxwpar.supabase.co/functions/v1/register' \
      -H 'Content-Type: application/json' \
      -d "{\"name\": \"$NAME\", \"cluster_uid\": \"$CLUSTER_UID\"}")

    if echo "$RESPONSE" | grep -q '"participant"'; then
      echo "✅ Successfully registered in tracking dashboard, getting temporary k8s credentials..."
      echo ""
    else
      echo "❌ Registration failed:"
      echo "$RESPONSE"
      exit 1
    fi
fi

echo "=================================================="
echo "  OpenCode + CAST AI Setup"
echo "=================================================="
echo ""

CASTAI_API_KEY="${CASTAI_API_KEY:-}"
if [ "$WITH_CASTAI" = true ] && [ -z "$CASTAI_API_KEY" ]; then
    # Prompt for CAST AI API key (for cluster management MCP)
    echo -e "${YELLOW}CAST AI API Key${NC}"
    echo "This key is used for the CAST AI MCP server (cluster management)."
    echo "Get one from: https://console.cast.ai/user/api-access -> Create access key"
    echo ""

    # Check if already configured
    EXISTING_KEY=""
    OPENCODE_CONFIG="$HOME/.config/opencode/opencode.json"
    if [ -f "$OPENCODE_CONFIG" ]; then
        EXISTING_KEY=$(python3 -c "
import json
try:
    with open('$OPENCODE_CONFIG') as f:
        config = json.load(f)
    print(config.get('mcp', {}).get('castai', {}).get('environment', {}).get('CASTAI_API_KEY', ''))
except:
    pass
" 2>/dev/null || true)
    fi

    if [ -n "$EXISTING_KEY" ]; then
        echo -e "Current key: ${BLUE}${EXISTING_KEY:0:8}...${NC}"
        read -r -p "Press ENTER to keep it, or paste a new key: " CASTAI_API_KEY
        if [ -z "$CASTAI_API_KEY" ]; then
            CASTAI_API_KEY="$EXISTING_KEY"
        fi
    else
        read -r -p "Enter your CAST AI API key: " CASTAI_API_KEY
        if [ -z "$CASTAI_API_KEY" ]; then
            echo -e "${YELLOW}No key entered. CAST AI MCP will not work without it.${NC}"
            echo -e "${YELLOW}You can re-run this script later to add it.${NC}"
            CASTAI_API_KEY="REPLACE_WITH_YOUR_CASTAI_API_KEY"
        fi
    fi
    echo ""
fi

# Create config directory
OPENCODE_CONFIG_DIR="$HOME/.config/opencode"
mkdir -p "$OPENCODE_CONFIG_DIR"

# Detect KUBECONFIG (use existing or default)
KUBECONFIG_PATH="${KUBECONFIG:-$HOME/.kube/config}"

# Build kubernetes MCP environment block (skip KUBECONFIG on Ubuntu, use default)
IS_UBUNTU=false
if [ -f /etc/os-release ] && grep -qi ubuntu /etc/os-release; then
    IS_UBUNTU=true
fi

KUBERNETES_MCP_ENV=""
if [ "$IS_UBUNTU" = false ]; then
    KUBERNETES_MCP_ENV=',
        "environment": {
          "KUBECONFIG": "'"$KUBECONFIG_PATH"'"
        }'
fi

# Build castai MCP block conditionally
CASTAI_MCP_BLOCK=""
if [ "$WITH_CASTAI" = true ] && [ -n "$CASTAI_API_KEY" ]; then
    CASTAI_MCP_BLOCK=',
    "castai": {
      "type": "local",
      "command": ["npx", "-y", "castai-mcp-server@latest"],
      "environment": {
        "CASTAI_API_KEY": "'"$CASTAI_API_KEY"'"
      }
    }'
fi

# Write OpenCode config
cat > "$OPENCODE_CONFIG_DIR/opencode.json" << OPENCODE_EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "permission": {
    "*": {
      "*": "allow"
    }
  },
  "mcp": {
    "kubernetes": {
      "type": "local",
      "command": ["npx", "-y", "kubernetes-mcp-server@latest"]$KUBERNETES_MCP_ENV
    }$CASTAI_MCP_BLOCK
  }
}
OPENCODE_EOF

# Install skills globally so they are available from any directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$SCRIPT_DIR/../../.opencode/skills"
SKILLS_DEST="$OPENCODE_CONFIG_DIR/skills"
if [ -d "$SKILLS_SRC" ]; then
    mkdir -p "$SKILLS_DEST"
    for skill_dir in "$SKILLS_SRC"/*/; do
        skill_name=$(basename "$skill_dir")
        ln -sf "$(cd "$skill_dir" && pwd)" "$SKILLS_DEST/$skill_name"
    done
fi

echo -e "${GREEN}OpenCode configured successfully!${NC}"
echo ""
if [ "$WITH_CASTAI" = true ] && [ -n "$CASTAI_API_KEY" ]; then
    echo "  MCP:      kubernetes + castai"
else
    echo "  MCP:      kubernetes"
fi
echo "  Config:   $OPENCODE_CONFIG_DIR/opencode.json"
if [ -d "$SKILLS_SRC" ]; then
    echo "  Skills:   $(ls "$SKILLS_SRC" | tr '\n' ' ')"
fi
echo ""
echo -e "  Run ${BLUE}opencode${NC} to start coding."
echo ""
