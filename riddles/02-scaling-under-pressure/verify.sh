#!/usr/bin/env bash

# Riddle 2: Scaling Under Pressure - Verification Script

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../common/lib.sh
source "$SCRIPT_DIR/../common/lib.sh"

echo "=================================================="
echo "  Riddle 2: Scaling Under Pressure - Verification"
echo "=================================================="
echo ""

# Check namespace exists
if ! kubectl get namespace riddle-2 &>/dev/null; then
    echo -e "${RED}Namespace 'riddle-2' not found. Run ./setup.sh first${NC}"
    exit 1
fi

# Run Go verifier
RESULT=$(run_verifier 2 riddle-2)
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
    echo -e "${GREEN}Riddle complete! All scaling infrastructure is configured.${NC}"
    echo ""
    echo "Summary:"
    echo "  - HPAs configured for web-frontend and order-service"
    echo "  - PodDisruptionBudgets protect availability during scaling"
    echo "  - Replicas distributed across nodes for resilience"
    echo ""
    echo "Next: Move to Riddle 3: cd ../03-the-slow-burn"
    echo ""
    exit 0
else
    echo -e "${RED}$FAIL check(s) still failing.${NC}"
    echo ""
    echo "Hints:"
    echo "  - Check HPAs:      kubectl get hpa -n riddle-2"
    echo "  - Check PDBs:      kubectl get pdb -n riddle-2"
    echo "  - Check pods:      kubectl get pods -n riddle-2 -o wide"
    echo "  - Check load:      kubectl top pods -n riddle-2"
    echo ""
    exit 1
fi
