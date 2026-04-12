#!/usr/bin/env bash

# Riddle 1: Advanced Cluster Debugging - Verification Script

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../common/lib.sh
source "$SCRIPT_DIR/../common/lib.sh"

echo "=================================================="
echo "  Riddle 1: Cluster Debugging - Verification"
echo "=================================================="
echo ""

# Check namespace exists
if ! kubectl get namespace riddle-1 &>/dev/null; then
    echo -e "${RED}Namespace 'riddle-1' not found. Run ./setup.sh first${NC}"
    exit 1
fi

# Run Go verifier
RESULT=$(run_verifier 1 riddle-1)
if [ -z "$RESULT" ]; then
    echo -e "${RED}Verifier returned no output. Is your kubeconfig configured?${NC}"
    exit 1
fi

echo "Running checks..."
echo ""

# Parse and display each check
TOTAL=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['total_checks'])")
PASS=0
i=0
while IFS= read -r check_json; do
    i=$((i + 1))
    name=$(echo "$check_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])")
    passed=$(echo "$check_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['passed'])")
    if [ "$passed" = "True" ]; then
        echo -e "  Check $i/$TOTAL: ${GREEN}PASS${NC} - $name"
        PASS=$((PASS + 1))
    else
        echo -e "  Check $i/$TOTAL: ${RED}FAIL${NC} - $name"
    fi
done < <(echo "$RESULT" | python3 -c "
import sys, json
for c in json.load(sys.stdin)['checks']:
    print(json.dumps(c))
")

FAIL=$((TOTAL - PASS))

echo ""
echo "=================================================="
echo -e "  Result: ${BLUE}$PASS/$TOTAL checks passed${NC}"
echo "=================================================="
echo ""

if [ "$PASS" -eq "$TOTAL" ]; then
    echo -e "${GREEN}All checks passed! Riddle complete.${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Set up CAST AI before Riddle 2 (if not done yet):"
    echo "     a. Create API key and configure OpenCode:"
    echo "        ./riddles/common/setup-opencode.sh --with-castai"
    echo "     b. Onboard your cluster to CAST AI console:"
    echo "        - Go to https://console.cast.ai -> Click 'Connect cluster' -> Select EKS"
    echo "        - Copy the read-only onboarding script and run it locally"
    echo "        - Click the green 'Enable CAST AI' button, copy the full onboarding script and run it locally"
    echo ""
    echo "  3. Move to Riddle 2: cd ../02-autoscaler-rebalancing"
    echo ""
    exit 0
else
    echo -e "${RED}$FAIL check(s) still failing.${NC}"
    echo ""
    exit 1
fi
