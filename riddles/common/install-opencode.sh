#!/usr/bin/env bash

# Install OpenCode (and npm on Ubuntu if missing)

set -e

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Install npm if missing on Ubuntu
if ! command -v npm &>/dev/null; then
    if [ -f /etc/os-release ] && grep -qi ubuntu /etc/os-release; then
        echo -e "${YELLOW}npm not found. Installing nodejs and npm...${NC}"
        sudo apt install nodejs npm -y
        echo ""
    fi
fi

# Install OpenCode if needed
if command -v opencode &>/dev/null; then
    echo -e "${GREEN}OpenCode is already installed.${NC}"
    exit 0
fi

echo -e "${YELLOW}OpenCode not found. Installing...${NC}"
if command -v brew &>/dev/null; then
    brew install opencode
elif command -v npm &>/dev/null; then
    npm install -g opencode-ai
elif command -v curl &>/dev/null; then
    curl -fsSL https://opencode.ai/install | bash
else
    echo -e "${RED}Cannot install OpenCode automatically. Please install from https://opencode.ai${NC}"
    exit 1
fi
echo ""
