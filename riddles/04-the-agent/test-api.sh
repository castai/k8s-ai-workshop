#!/usr/bin/env bash
# Quick connectivity test for the Kimchi LLM API.
# Usage: ./test-api.sh [API_KEY]
#   or:  KIMCHI_API_KEY=<key> ./test-api.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/lib.sh"

API_KEY="${1:-${KIMCHI_API_KEY:-${CASTAI_API_KEY:-}}}"
BASE_URL="https://llm.kimchi.dev/openai/v1"
MODEL="kimi-k2.5"

echo ""
echo -e "  ${BOLD}Kimchi API Test${NC}"
echo ""

# --- Validate / prompt for API key -----------------------------------------
if [ -z "$API_KEY" ]; then
  echo -e "  ${YELLOW}No API key found.${NC}"
  echo ""
  echo -e "      Get one at ${BLUE}https://kimchi.dev${NC} > Account > API Keys"
  echo ""
  read -rp "  Enter your Kimchi API key: " API_KEY
  echo ""

  if [ -z "$API_KEY" ]; then
    printf "  ${RED}[x]${NC} No API key provided. Exiting.\n"
    echo ""
    exit 1
  fi
fi
printf "  ${GREEN}[ok]${NC} API key provided\n"

# --- Check connectivity ----------------------------------------------------
printf "  [ ] Calling ${MODEL} via Kimchi API..."

RESPONSE=$(curl -s -w "\n%{http_code}" "$BASE_URL/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "'"$MODEL"'",
    "messages": [{"role": "user", "content": "How many days in a year? Answer briefly."}],
    "max_tokens": 500
  }' 2>&1) || true

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
  CONTENT=$(echo "$BODY" | python3 -c "
import sys, json
data = json.load(sys.stdin)
msg = data['choices'][0]['message']
print(msg.get('content') or msg.get('reasoning_content') or '(empty response)')
" 2>/dev/null) || CONTENT="(could not parse response)"

  printf "\r  ${GREEN}[ok]${NC} Calling ${MODEL} via Kimchi API\n"
  echo ""
  echo -e "      ${DIM}Model response:${NC} $CONTENT"
else
  printf "\r  ${RED}[x]${NC} Calling ${MODEL} via Kimchi API (HTTP $HTTP_CODE)\n"
  echo ""
  echo -e "      ${DIM}Response:${NC}"
  echo "$BODY" | python3 -m json.tool 2>/dev/null | sed 's/^/      /' || echo "$BODY" | sed 's/^/      /'
  echo ""
  exit 1
fi

echo ""
echo -e "  ${GREEN}${BOLD}API is working!${NC} You're ready to build your agent."
echo ""
