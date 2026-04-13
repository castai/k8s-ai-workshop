#!/usr/bin/env bash

# Install OpenCode via the official install script

set -e

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Install OpenCode if needed
if command -v opencode &>/dev/null; then
    echo -e "${GREEN}OpenCode is already installed.${NC}"
    exit 0
fi

echo -e "${YELLOW}OpenCode not found. Installing...${NC}"
curl -fsSL https://opencode.ai/install | bash
echo ""
