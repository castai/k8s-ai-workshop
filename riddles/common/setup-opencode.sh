#!/usr/bin/env bash

# Configure OpenCode MCP servers and skills

set -e

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Register participant name in the Loveable dashboard (once, tracked via state file).
# Skip entirely in CI to avoid polluting the shared Supabase dashboard.
if [ "${CI:-}" != "true" ] && ! state_done "participant-registered"; then
    # Use PARTICIPANT_NAME env var if set (from setup.sh), otherwise prompt
    if [ -n "${PARTICIPANT_NAME:-}" ]; then
        NAME="$PARTICIPANT_NAME"
    elif [ -t 0 ]; then
        read -p "Enter your name: " NAME
    else
        NAME="anonymous"
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

# Resolve API key: env var > kimchi config file > empty (provider section skipped)
CASTAI_API_KEY="${KIMCHI_API_KEY:-${CASTAI_API_KEY:-}}"
if [ -z "$CASTAI_API_KEY" ] && [ -f "$HOME/.config/kimchi/config.json" ]; then
    CASTAI_API_KEY=$(python3 -c "import json; print(json.load(open('$HOME/.config/kimchi/config.json')).get('api_key',''))" 2>/dev/null || echo "")
fi

python3 - "$OPENCODE_CONFIG" "$KUBERNETES_MCP" "$CASTAI_API_KEY" << 'PYEOF'
import json, sys

config_path = sys.argv[1]
k8s_mcp = json.loads(sys.argv[2])
api_key = sys.argv[3]

# Load existing config or start fresh
try:
    with open(config_path) as f:
        config = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    config = {}

# Patch in required keys (preserve everything else)
config["$schema"] = "https://opencode.ai/config.json"
config["compaction"] = {"auto": True}
config["model"] = "kimchi/kimi-k2.5"
config.setdefault("permission", {}).setdefault("*", {})["*"] = "allow"
config.setdefault("mcp", {})["kubernetes"] = k8s_mcp
config["plugin"] = [
    "@kimchi-dev/opencode-kimchi@1.0.1"
]
config["provider"] = {
    "kimchi": {
        "name": "Kimchi",
        "npm": "@ai-sdk/openai-compatible",
        "options": {
            "apiKey": api_key,
            "baseURL": "https://llm.kimchi.dev/openai/v1",
            "litellmProxy": True,
        },
        "models": {
            "kimi-k2.5": {
                "name": "kimi-k2.5",
                "reasoning": True,
                "tool_call": True,
                "limit": {"context": 262144, "output": 32768},
            },
            "minimax-m2.7": {
                "name": "minimax-m2.7",
                "reasoning": True,
                "tool_call": True,
                "limit": {"context": 196608, "output": 32768},
            },
            "nemotron-3-super-fp4": {
                "name": "nemotron-3-super-fp4",
                "reasoning": True,
                "tool_call": True,
                "limit": {"context": 1048576, "output": 256000},
            },
        },
    }
}

with open(config_path, "w") as f:
    json.dump(config, f, indent=2)
    f.write("\n")
PYEOF

# Install skills globally so they are available from any directory
# Copy files instead of symlinking directories -- kimchi's config copy
# fails with "copy_file_range: is a directory" on directory symlinks.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$SCRIPT_DIR/../../.opencode/skills"
SKILLS_DEST="$OPENCODE_CONFIG_DIR/skills"
if [ -d "$SKILLS_SRC" ]; then
    for skill_dir in "$SKILLS_SRC"/*/; do
        skill_name=$(basename "$skill_dir")
        mkdir -p "$SKILLS_DEST/$skill_name"
        cp -f "$skill_dir"* "$SKILLS_DEST/$skill_name/"
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
