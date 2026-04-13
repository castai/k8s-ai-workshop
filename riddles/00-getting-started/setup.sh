#!/usr/bin/env bash

# Step 0: Getting Started - Kimchi CLI + OpenCode bootstrap
# Usage: ./setup.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../common/lib.sh
source "$SCRIPT_DIR/../common/lib.sh"

echo "=================================================="
echo "  Step 0: Getting Started - Kimchi CLI Setup"
echo "=================================================="
echo ""

# --- Stage 1: Prompt for API key if not set --------------------------------
CASTAI_API_KEY="${KIMCHI_API_KEY:-${CASTAI_API_KEY:-}}"

if [ -z "$CASTAI_API_KEY" ]; then
    echo -e "${YELLOW}You need a Kimchi API key to continue.${NC}"
    echo ""
    echo "  1. Go to https://kimchi.dev"
    echo "  2. Register or log in"
    echo "  3. Navigate to Account > API Keys"
    echo "  4. Create a new key and paste it below"
    echo ""
    read -p "  Enter your Kimchi API key: " CASTAI_API_KEY
    echo ""

    if [ -z "$CASTAI_API_KEY" ]; then
        echo -e "${RED}[x] No API key provided. Exiting.${NC}"
        exit 1
    fi

    export KIMCHI_API_KEY="$CASTAI_API_KEY"
    export CASTAI_API_KEY
fi

# --- Stage 2: Collect participant name (before bootstrap, which hides prompts)
if [ -z "${PARTICIPANT_NAME:-}" ]; then
    read -p "  Enter your name (for the dashboard): " PARTICIPANT_NAME
    export PARTICIPANT_NAME
fi

# --- Stage 3: Run bootstrap ------------------------------------------------
"$SCRIPT_DIR/../common/bootstrap.sh"
