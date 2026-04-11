#!/bin/bash
# Strigo lab init script for kimchi-cli v0.1.27
set -e

KIMCHI_API_KEY="${KIMCHI_API_KEY:-YOUR_API_KEY}"
KIMCHI_VERSION="v0.1.27"

if [ "$KIMCHI_API_KEY" = "YOUR_API_KEY" ] || [ -z "$KIMCHI_API_KEY" ]; then
  echo "ERROR: KIMCHI_API_KEY is not set." >&2
  echo "Usage: KIMCHI_API_KEY=<your-key> $0" >&2
  exit 1
fi

# 1. Install kimchi (pinned version, no TUI launch)
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "$ARCH" in x86_64) ARCH="amd64" ;; aarch64|arm64) ARCH="arm64" ;; esac

curl -fsSL "https://github.com/castai/kimchi/releases/download/${KIMCHI_VERSION}/kimchi_${OS}_${ARCH}.tar.gz" \
  | tar -xzf - -C /tmp
chmod +x /tmp/kimchi
mv /tmp/kimchi /usr/local/bin/kimchi

# 2. Create config — skips TUI entirely
mkdir -p ~/.config/kimchi
cat > ~/.config/kimchi/config.json << EOF
{
  "api_key": "${KIMCHI_API_KEY}",
  "mode": "inject",
  "selected_tools": ["opencode"],
  "scope": "global",
  "telemetry_enabled": true,
  "telemetry_notice_shown": true
}
EOF
chmod 600 ~/.config/kimchi/config.json

# 3. Export env var + alias
cat >> ~/.bashrc << 'PROFILE'
export KIMCHI_API_KEY="__KEY__"
alias opencode="kimchi opencode"
PROFILE
sed -i "s|__KEY__|${KIMCHI_API_KEY}|g" ~/.bashrc
source ~/.bashrc
