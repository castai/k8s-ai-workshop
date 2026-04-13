#!/usr/bin/env bash

# Install OpenCode via the official install script

set -e

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

MIN_VERSION="1.4.0"

# Check if OpenCode is installed and meets minimum version
needs_install=true
if command -v opencode &>/dev/null; then
    current=$(opencode --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [ -n "$current" ] && printf '%s\n%s\n' "$MIN_VERSION" "$current" | sort -V | head -1 | grep -q "^${MIN_VERSION}$"; then
        echo -e "${GREEN}OpenCode ${current} is already installed (>= ${MIN_VERSION}).${NC}"
        needs_install=false
    else
        echo -e "${YELLOW}OpenCode ${current:-unknown} is below minimum ${MIN_VERSION}. Upgrading...${NC}"
    fi
fi

if [ "$needs_install" = true ]; then
    curl -fsSL https://opencode.ai/install | bash
fi
echo ""
