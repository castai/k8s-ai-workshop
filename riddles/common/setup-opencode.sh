#!/usr/bin/env bash

# Configure OpenCode MCP servers and skills

set -e

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Register participant name in the Loveable dashboard (once, tracked via state file).
if ! state_done "participant-registered"; then
    # Use PARTICIPANT_NAME env var if set (from setup.sh), otherwise prompt or default
    if [ -n "${PARTICIPANT_NAME:-}" ]; then
        NAME="$PARTICIPANT_NAME"
    elif [ -t 0 ]; then
        read -p "Enter your name: " NAME
    else
        NAME="ci-runner"
    fi

    CLUSTER_UID=$(kubectl get namespace kube-system -o jsonpath='{.metadata.uid}' 2>/dev/null || echo "")

    REGISTERED=false
    if [ -n "$CLUSTER_UID" ]; then
        for attempt in 1 2 3; do
            RESPONSE=$(curl -s --connect-timeout 5 -m 10 \
              -X POST 'https://hsnxzbyedgzepraxwpar.supabase.co/functions/v1/register' \
              -H 'Content-Type: application/json' \
              -d "{\"name\": \"$NAME\", \"cluster_uid\": \"$CLUSTER_UID\"}" 2>/dev/null || echo "")

            if echo "$RESPONSE" | grep -q '"participant"'; then
                echo "✅ Successfully registered in tracking dashboard"
                echo ""
                REGISTERED=true
                break
            fi
            [ "$attempt" -lt 3 ] && sleep 2
        done
    fi

    if [ "$REGISTERED" = true ]; then
        state_mark "participant-registered"
    else
        echo -e "${YELLOW}⚠ Dashboard registration failed (network issue or service unavailable)${NC}"
        echo -e "${YELLOW}  The workshop will work fine — progress tracking won't appear on the dashboard.${NC}"
        echo -e "${YELLOW}  You can retry later by running: rm -f ~/.config/workshop/state && $0${NC}"
        echo ""
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

# Patch OpenCode config (merge required keys, preserve existing settings)
OPENCODE_CONFIG="$OPENCODE_CONFIG_DIR/opencode.json"

# Build the patch payload
KUBERNETES_MCP='{"type": "local", "command": ["npx", "-y", "kubernetes-mcp-server@latest"]}'
if [ "$IS_UBUNTU" = false ]; then
    KUBERNETES_MCP=$(python3 -c "
import json
mcp = json.loads('$KUBERNETES_MCP')
mcp['environment'] = {'KUBECONFIG': '$KUBECONFIG_PATH'}
print(json.dumps(mcp))
")
fi

python3 - "$OPENCODE_CONFIG" "$KUBERNETES_MCP" << 'PYEOF'
import json, sys

config_path = sys.argv[1]
k8s_mcp = json.loads(sys.argv[2])

# Load existing config or start fresh
try:
    with open(config_path) as f:
        config = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    config = {}

# Patch in required keys (preserve everything else)
config.setdefault("$schema", "https://opencode.ai/config.json")
config.setdefault("permission", {}).setdefault("*", {})["*"] = "allow"
config.setdefault("mcp", {})["kubernetes"] = k8s_mcp

with open(config_path, "w") as f:
    json.dump(config, f, indent=2)
    f.write("\n")
PYEOF

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
