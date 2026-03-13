#!/usr/bin/env bash

# Riddle 2: Autoscaler & Rebalancing - Verification Script

set +e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=================================================="
echo "  Riddle 2: Autoscaler & Rebalancing - Verification"
echo "=================================================="
echo ""

# Check namespace exists
if ! kubectl get namespace riddle-2 &>/dev/null; then
    echo -e "${RED}Namespace 'riddle-2' not found. Run ./setup.sh first${NC}"
    exit 1
fi

PASS=0
FAIL=0

run_check() {
    local n=$1
    local total=$2
    local desc=$3
    local result=$4
    if [ "$result" = "true" ]; then
        echo -e "  Check $n/$total: ${GREEN}PASS${NC} - $desc"
        ((PASS++))
    else
        echo -e "  Check $n/$total: ${RED}FAIL${NC} - $desc"
        ((FAIL++))
    fi
}

# =========================================================
# Step 1 Checks: Autoscaling (pods running)
# =========================================================
STEP1_TOTAL=4

echo -e "${BLUE}Step 1: Autoscaling${NC}"
echo ""

# Check 1: All deployments have desired replicas running
ALL_DEPLOY_READY="true"
for deploy in $(kubectl get deployments -n riddle-2 -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    DESIRED=$(kubectl get deployment "$deploy" -n riddle-2 -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    READY=$(kubectl get deployment "$deploy" -n riddle-2 -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    READY=${READY:-0}
    if [ "$READY" -ne "$DESIRED" ]; then
        ALL_DEPLOY_READY="false"
        echo -e "    ${YELLOW}↳ $deploy: $READY/$DESIRED ready${NC}"
    fi
done
run_check 1 "$STEP1_TOTAL" "All deployments have desired replicas ready" "$ALL_DEPLOY_READY"

# Check 2: No pods in Pending state
PENDING=$(kubectl get pods -n riddle-2 --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l | tr -d ' ')
PENDING_OK="$([ "$PENDING" -eq 0 ] && echo true || echo false)"
if [ "$PENDING_OK" = "false" ]; then
    echo -e "    ${YELLOW}↳ $PENDING pod(s) still Pending${NC}"
fi
run_check 2 "$STEP1_TOTAL" "No pods in Pending state" "$PENDING_OK"

# Check 3: No pods in error states (exclude completed Job pods)
BAD_PODS=$(kubectl get pods -n riddle-2 --no-headers 2>/dev/null | grep -v 'Completed' | grep -cE 'CrashLoopBackOff|ImagePullBackOff|Error|ErrImagePull|CreateContainerConfigError' || true)
ERRORS_OK="$([ "$BAD_PODS" -eq 0 ] && echo true || echo false)"
if [ "$ERRORS_OK" = "false" ]; then
    echo -e "    ${YELLOW}↳ $BAD_PODS pod(s) in error state${NC}"
fi
run_check 3 "$STEP1_TOTAL" "No pods in error states" "$ERRORS_OK"

# Check 4: All deployment pods fully Ready (exclude completed Job pods)
RUNNING_PODS=$(kubectl get pods -n riddle-2 --no-headers 2>/dev/null | grep -v 'Completed' | wc -l | tr -d ' ')
NOT_READY=$(kubectl get pods -n riddle-2 --no-headers 2>/dev/null | grep -v 'Completed' | awk '{split($2,a,"/"); if(a[1]!=a[2]) print}' | wc -l | tr -d ' ')
READY_OK="$([ "$NOT_READY" -eq 0 ] && [ "$RUNNING_PODS" -gt 0 ] && echo true || echo false)"
if [ "$READY_OK" = "false" ]; then
    echo -e "    ${YELLOW}↳ $NOT_READY pod(s) not fully ready (running: $RUNNING_PODS)${NC}"
fi
run_check 4 "$STEP1_TOTAL" "All deployment pods fully Ready" "$READY_OK"

STEP1_PASS=$PASS

echo ""

# =========================================================
# Step 2 Checks: Rebalancing (via CAST AI API)
# =========================================================
STEP2_TOTAL=1

echo -e "${BLUE}Step 2: Rebalancing${NC}"
echo ""

# Check 5: CAST AI API shows a completed rebalancing plan
# Extract API key from OpenCode config
OPENCODE_CONFIG="$HOME/.config/opencode/opencode.json"
CASTAI_API_KEY=""
if [ -f "$OPENCODE_CONFIG" ]; then
    CASTAI_API_KEY=$(python3 -c "
import json, sys
try:
    with open('$OPENCODE_CONFIG') as f:
        config = json.load(f)
    env = config.get('mcp', {}).get('castai', {}).get('environment', {})
    print(env.get('CASTAI_API_KEY', ''))
except:
    pass
" 2>/dev/null)
fi

REBALANCE_OK="false"
if [ -z "$CASTAI_API_KEY" ] || [ "$CASTAI_API_KEY" = "REPLACE_WITH_YOUR_CASTAI_API_KEY" ]; then
    echo -e "    ${YELLOW}↳ Could not find CAST AI API key in OpenCode config${NC}"
    echo -e "    ${YELLOW}  Run: ../common/setup-opencode.sh --with-castai${NC}"
else
    # Get cluster ID from CAST AI API
    CLUSTERS_RESPONSE=$(curl -s -H "X-API-Key: $CASTAI_API_KEY" \
        "https://api.cast.ai/v1/kubernetes/external-clusters" 2>/dev/null)

    CLUSTER_ID=$(echo "$CLUSTERS_RESPONSE" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    clusters = data.get('items', [])
    if clusters:
        print(clusters[0]['id'])
except:
    pass
" 2>/dev/null)

    if [ -z "$CLUSTER_ID" ]; then
        echo -e "    ${YELLOW}↳ Could not find cluster in CAST AI account${NC}"
        echo -e "    ${YELLOW}  Ensure your cluster is onboarded to CAST AI${NC}"
    else
        # Query rebalancing plans for the cluster
        PLANS_RESPONSE=$(curl -s -H "X-API-Key: $CASTAI_API_KEY" \
            "https://api.cast.ai/v1/kubernetes/clusters/$CLUSTER_ID/rebalancing-plans" 2>/dev/null)

        COMPLETED_COUNT=$(echo "$PLANS_RESPONSE" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    plans = data.get('items', [])
    completed = [p for p in plans if p.get('status') == 'finished']
    print(len(completed))
except:
    print(0)
" 2>/dev/null)

        if [ "$COMPLETED_COUNT" -gt 0 ]; then
            REBALANCE_OK="true"
            echo -e "    ${GREEN}↳ Found $COMPLETED_COUNT completed rebalancing plan(s) in CAST AI${NC}"
        else
            echo -e "    ${YELLOW}↳ No completed rebalancing plans found${NC}"
            echo -e "    ${YELLOW}  Trigger rebalancing via CAST AI MCP and wait for it to complete${NC}"
        fi
    fi
fi
run_check 5 "$(( STEP1_TOTAL + STEP2_TOTAL ))" "CAST AI rebalancing completed successfully" "$REBALANCE_OK"

TOTAL=$((STEP1_TOTAL + STEP2_TOTAL))

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
