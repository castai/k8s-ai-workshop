#!/usr/bin/env bash

# Riddle 2: Autoscaler & Rebalancing - Verification Script

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../common/lib.sh
source "$SCRIPT_DIR/../common/lib.sh"

echo "=================================================="
echo "  Riddle 2: Autoscaler & Rebalancing - Verification"
echo "=================================================="
echo ""

# Check namespace exists
if ! kubectl get namespace riddle-2 &>/dev/null; then
    echo -e "${RED}Namespace 'riddle-2' not found. Run ./setup.sh first${NC}"
    exit 1
fi

# Run Go verifier (lib.sh exports CASTAI_API_KEY from OpenCode config)
RESULT=$(run_verifier 2 riddle-2)
if [ -z "$RESULT" ]; then
    echo -e "${RED}Verifier returned no output. Is your kubeconfig configured?${NC}"
    exit 1
fi

# Parse check results into arrays
STEP1_TOTAL=4
STEP2_TOTAL=1
TOTAL=$((STEP1_TOTAL + STEP2_TOTAL))
PASS=0

# Extract all check results
readarray -t NAMES < <(echo "$RESULT" | python3 -c "
import sys, json
for c in json.load(sys.stdin)['checks']:
    print(c['name'])
")
readarray -t PASSED < <(echo "$RESULT" | python3 -c "
import sys, json
for c in json.load(sys.stdin)['checks']:
    print(c['passed'])
")

# Step 1: Autoscaling checks (first 4)
echo -e "${BLUE}Step 1: Autoscaling${NC}"
echo ""

STEP1_PASS=0
for i in 0 1 2 3; do
    n=$((i + 1))
    if [ "${PASSED[$i]}" = "True" ]; then
        echo -e "  Check $n/$STEP1_TOTAL: ${GREEN}PASS${NC} - ${NAMES[$i]}"
        STEP1_PASS=$((STEP1_PASS + 1))
        PASS=$((PASS + 1))
    else
        echo -e "  Check $n/$STEP1_TOTAL: ${RED}FAIL${NC} - ${NAMES[$i]}"
    fi
done

echo ""

# Step 2: Rebalancing check (check 5)
echo -e "${BLUE}Step 2: Rebalancing${NC}"
echo ""

if [ "${PASSED[4]}" = "True" ]; then
    echo -e "  Check 5/$TOTAL: ${GREEN}PASS${NC} - ${NAMES[4]}"
    PASS=$((PASS + 1))
else
    echo -e "  Check 5/$TOTAL: ${RED}FAIL${NC} - ${NAMES[4]}"
fi

echo ""
echo "=================================================="
echo -e "  Result: ${BLUE}$PASS/$TOTAL checks passed${NC}"
echo "=================================================="
echo ""

if [ "$PASS" -eq "$TOTAL" ]; then
    echo -e "${GREEN}Riddle complete! Autoscaling and rebalancing both succeeded.${NC}"
    echo ""
    echo "Summary:"
    echo "  - All persistent services are running and healthy"
    echo "  - Batch jobs completed, freeing up cluster capacity"
    echo "  - CAST AI rebalanced the cluster to remove excess nodes"
    echo ""
    exit 0
elif [ "$STEP1_PASS" -eq "$STEP1_TOTAL" ]; then
    echo -e "${GREEN}Step 1 complete!${NC} All pods are running."
    echo ""
    echo -e "${YELLOW}Step 2 remaining:${NC} Rebalancing checks not yet passing."
    echo ""
    echo "Next steps:"
    echo "  1. Trigger rebalancing via CAST AI MCP"
    echo "  2. Wait for rebalancing to complete, then re-run ./verify.sh"
    echo ""
    exit 1
else
    STEP1_FAIL=$((STEP1_TOTAL - STEP1_PASS))
    echo -e "${RED}Step 1: $STEP1_FAIL check(s) still failing.${NC}"
    echo ""
    echo "Hints:"
    echo "  - Use CAST AI MCP to enable the autoscaler"
    echo "  - Ask: 'Enable autoscaler for my cluster to handle pending pods'"
    echo ""
    exit 1
fi
