#!/usr/bin/env bash

# Configure OpenCode MCP servers and skills

set -e

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Register participant name in the Loveable dashboard (once, tracked via state file).
if ! state_done "participant-registered"; then
    read -p "Enter your name: " NAME

    CLUSTER_UID=$(kubectl get namespace kube-system -o jsonpath='{.metadata.uid}')

    RESPONSE=$(curl -s -X POST 'https://hsnxzbyedgzepraxwpar.supabase.co/functions/v1/register' \
      -H 'Content-Type: application/json' \
      -d "{\"name\": \"$NAME\", \"cluster_uid\": \"$CLUSTER_UID\"}")

    if echo "$RESPONSE" | grep -q '"participant"'; then
      echo "✅ Successfully registered in tracking dashboard"
      echo ""
      state_mark "participant-registered"
    else
      echo "❌ Registration failed:"
      echo "$RESPONSE"
      exit 1
    fi
else
    printf "  ${GREEN}[✓]${NC} Participant registered ${DIM}(cached)${NC}\n"
fi

echo "=================================================="
echo "  OpenCode Setup"
echo "=================================================="
echo ""

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
    }
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
echo "  MCP:      kubernetes"
echo "  Config:   $OPENCODE_CONFIG_DIR/opencode.json"
if [ -d "$SKILLS_SRC" ]; then
    echo "  Skills:   $(ls "$SKILLS_SRC" | tr '\n' ' ')"
fi
echo ""
echo -e "  Run ${BLUE}opencode${NC} to start coding."
echo ""
