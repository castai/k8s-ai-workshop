#!/usr/bin/env bash

# Riddle 1: Advanced Cluster Debugging - Verification Script

set +e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=================================================="
echo "  Riddle 1: Cluster Debugging - Verification"
echo "=================================================="
echo ""

PASS=0
FAIL=0
TOTAL=10

# Check namespace exists
if ! kubectl get namespace riddle-1 &>/dev/null; then
    echo -e "${RED}Namespace 'riddle-1' not found. Run ./setup.sh first${NC}"
    exit 1
fi

run_check() {
    local n=$1
    local result=$2
    if [ "$result" = "true" ]; then
        echo -e "  Check $n/$TOTAL: ${GREEN}PASS${NC}"
        ((PASS++))
    else
        echo -e "  Check $n/$TOTAL: ${RED}FAIL${NC}"
        ((FAIL++))
    fi
}

echo "Running checks..."
echo ""

# Check 1: All deployments have desired replicas running
ALL_DEPLOY_READY="true"
for deploy in $(kubectl get deployments -n riddle-1 -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    DESIRED=$(kubectl get deployment "$deploy" -n riddle-1 -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    READY=$(kubectl get deployment "$deploy" -n riddle-1 -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    READY=${READY:-0}
    if [ "$READY" -ne "$DESIRED" ]; then
        ALL_DEPLOY_READY="false"
        break
    fi
done
run_check 1 "$ALL_DEPLOY_READY"

# Check 2: No pods in Pending state
PENDING=$(kubectl get pods -n riddle-1 --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l | tr -d ' ')
run_check 2 "$([ "$PENDING" -eq 0 ] && echo true || echo false)"

# Check 3: No pods in error states
BAD_PODS=$(kubectl get pods -n riddle-1 --no-headers 2>/dev/null | grep -cE 'CrashLoopBackOff|ImagePullBackOff|Error|ErrImagePull|CreateContainerConfigError' || true)
run_check 3 "$([ "$BAD_PODS" -eq 0 ] && echo true || echo false)"

# Check 4: All init containers completed
INIT_PENDING=$(kubectl get pods -n riddle-1 --no-headers 2>/dev/null | grep -c 'Init:' || true)
PODS_WITH_INIT=$(kubectl get pods -n riddle-1 -o jsonpath='{range .items[*]}{.spec.initContainers[*].name}{"\n"}{end}' 2>/dev/null | grep -c '.' || true)
run_check 4 "$([ "$INIT_PENDING" -eq 0 ] && [ "$PODS_WITH_INIT" -gt 0 ] && echo true || echo false)"

# Check 5: All pods fully Ready (N/N)
TOTAL_PODS=$(kubectl get pods -n riddle-1 --no-headers 2>/dev/null | wc -l | tr -d ' ')
NOT_READY=$(kubectl get pods -n riddle-1 --no-headers 2>/dev/null | awk '{split($2,a,"/"); if(a[1]!=a[2]) print}' | wc -l | tr -d ' ')
run_check 5 "$([ "$NOT_READY" -eq 0 ] && [ "$TOTAL_PODS" -gt 0 ] && echo true || echo false)"

# Check 6: All services have endpoints
ALL_SVC_OK="true"
for svc in $(kubectl get svc -n riddle-1 -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    ANNOTATIONS=$(kubectl get svc "$svc" -n riddle-1 -o jsonpath='{.metadata.annotations.status}' 2>/dev/null || echo "")
    if [ "$ANNOTATIONS" = "pending-deployment" ]; then
        continue
    fi
    ENDPOINTS=$(kubectl get endpoints "$svc" -n riddle-1 -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
    if [ -z "$ENDPOINTS" ]; then
        ALL_SVC_OK="false"
        break
    fi
done
run_check 6 "$ALL_SVC_OK"

# Check 7: Entry point is accessible
EP_OK="false"
if curl -s -f -m 5 http://localhost:8080 >/dev/null 2>&1; then
    EP_OK="true"
fi
run_check 7 "$EP_OK"

# Check 8: Core services reachable from within cluster
ALL_REACH="true"
TESTER_POD=$(kubectl get pods -l app=config-service -n riddle-1 -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$TESTER_POD" ]; then
    for svc in order-service inventory-service notification-service payment-processor-svc search-service recommendation-service; do
        RESULT=$(kubectl exec "$TESTER_POD" -n riddle-1 -- wget -q -O- -T 3 "http://${svc}:8080/health" 2>&1 || echo "FAILED")
        if ! echo "$RESULT" | grep -q "healthy"; then
            ALL_REACH="false"
            break
        fi
    done
else
    ALL_REACH="false"
fi
run_check 8 "$ALL_REACH"

# Check 9: Analytics service operational
ANALYTICS_OK="false"
if [ -n "$TESTER_POD" ]; then
    RESULT=$(kubectl exec "$TESTER_POD" -n riddle-1 -- wget -q -O- -T 3 "http://analytics-service:8080/health" 2>&1 || echo "FAILED")
    if echo "$RESULT" | grep -q "healthy"; then
        ANALYTICS_OK="true"
    fi
fi
run_check 9 "$ANALYTICS_OK"

# Check 10: Dashboard reports all nominal
DASH_OK="false"
DASH_CONTENT=$(curl -s -m 5 http://localhost:8080 2>/dev/null || echo "")
if echo "$DASH_CONTENT" | grep -q "All systems nominal"; then
    DASH_OK="true"
fi
run_check 10 "$DASH_OK"

echo ""
echo "=================================================="
echo -e "  Result: ${BLUE}$PASS/$TOTAL checks passed${NC}"
echo "=================================================="
echo ""

if [ "$PASS" -eq "$TOTAL" ]; then
    echo -e "${GREEN}All checks passed! Riddle complete.${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Clean up: ./reset.sh"
    echo ""
    echo "  2. Set up CAST AI before Riddle 2 (if not done yet):"
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
