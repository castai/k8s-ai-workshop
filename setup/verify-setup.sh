#!/usr/bin/env bash

# Kubernetes Workshop - Cluster Verification Script
# Verifies that the kind cluster is properly set up and healthy

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=================================================="
echo "  Kubernetes Workshop - Cluster Verification"
echo "=================================================="
echo ""

ERRORS=0
WARNINGS=0

# Function to check and print result
check_pass() {
    echo -e "${GREEN}✅ $1${NC}"
}

check_fail() {
    echo -e "${RED}❌ $1${NC}"
    ((ERRORS++))
}

check_warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    ((WARNINGS++))
}

# 1. Check cluster exists
echo "🔍 Checking cluster existence..."
if kind get clusters 2>/dev/null | grep -q "^workshop-cluster$"; then
    check_pass "Cluster 'workshop-cluster' exists"
else
    check_fail "Cluster 'workshop-cluster' not found"
    echo "   Run: ./setup/install-kind.sh"
    exit 1
fi
echo ""

# 2. Check kubectl context
echo "🔍 Checking kubectl context..."
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "")
if [ "$CURRENT_CONTEXT" == "kind-workshop-cluster" ]; then
    check_pass "kubectl context is set to 'kind-workshop-cluster'"
else
    check_warn "kubectl context is '$CURRENT_CONTEXT', expected 'kind-workshop-cluster'"
    echo "   Run: kubectl config use-context kind-workshop-cluster"
fi
echo ""

# 3. Check cluster connectivity
echo "🔍 Checking cluster connectivity..."
if kubectl cluster-info &>/dev/null; then
    check_pass "Can connect to cluster"
else
    check_fail "Cannot connect to cluster"
fi
echo ""

# 4. Check nodes
echo "🔍 Checking nodes..."
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready " || true)

if [ "$NODE_COUNT" -eq 4 ]; then
    check_pass "Found 4 nodes (expected: 1 control-plane + 3 workers)"
else
    check_warn "Found $NODE_COUNT nodes, expected 4"
fi

if [ "$READY_NODES" -eq "$NODE_COUNT" ]; then
    check_pass "All $NODE_COUNT nodes are Ready"
else
    check_fail "Only $READY_NODES of $NODE_COUNT nodes are Ready"
fi

# Show node details
echo ""
echo -e "${BLUE}Node details:${NC}"
kubectl get nodes -o wide
echo ""

# 5. Check node labels
echo "🔍 Checking node labels..."
CONTROL_PLANE_COUNT=$(kubectl get nodes -l workshop-role=control-plane --no-headers 2>/dev/null | wc -l | tr -d ' ')
WORKER_COUNT=$(kubectl get nodes -l workshop-role=worker --no-headers 2>/dev/null | wc -l | tr -d ' ')

if [ "$CONTROL_PLANE_COUNT" -eq 1 ]; then
    check_pass "Found 1 control-plane node with correct label"
else
    check_warn "Found $CONTROL_PLANE_COUNT control-plane nodes with workshop-role label"
fi

if [ "$WORKER_COUNT" -eq 3 ]; then
    check_pass "Found 3 worker nodes with correct labels"
else
    check_warn "Found $WORKER_COUNT worker nodes with workshop-role label"
fi
echo ""

# 6. Check system pods
echo "🔍 Checking system pods..."
SYSTEM_PODS_TOTAL=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | wc -l | tr -d ' ')
SYSTEM_PODS_RUNNING=$(kubectl get pods -n kube-system --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')

if [ "$SYSTEM_PODS_RUNNING" -eq "$SYSTEM_PODS_TOTAL" ] && [ "$SYSTEM_PODS_TOTAL" -gt 0 ]; then
    check_pass "All $SYSTEM_PODS_TOTAL system pods are Running"
else
    check_warn "$SYSTEM_PODS_RUNNING of $SYSTEM_PODS_TOTAL system pods are Running"
    echo ""
    echo -e "${BLUE}System pod status:${NC}"
    kubectl get pods -n kube-system
fi
echo ""

# 7. Check core components
echo "🔍 Checking core components..."
COMPONENTS=("kube-apiserver" "kube-controller-manager" "kube-scheduler" "etcd" "coredns" "kube-proxy")

for component in "${COMPONENTS[@]}"; do
    POD_COUNT=$(kubectl get pods -n kube-system -l tier=control-plane -l component="$component" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$POD_COUNT" -eq 0 ]; then
        # Try alternative label
        POD_COUNT=$(kubectl get pods -n kube-system -l k8s-app="$component" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    fi

    if [ "$POD_COUNT" -gt 0 ]; then
        RUNNING_COUNT=$(kubectl get pods -n kube-system -l component="$component" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
        if [ "$RUNNING_COUNT" -eq 0 ]; then
            RUNNING_COUNT=$(kubectl get pods -n kube-system -l k8s-app="$component" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
        fi

        if [ "$RUNNING_COUNT" -gt 0 ]; then
            check_pass "Component $component is running"
        else
            check_warn "Component $component found but not running"
        fi
    else
        check_warn "Component $component not found"
    fi
done
echo ""

# 8. Check CNI (networking)
echo "🔍 Checking CNI networking..."
CNI_PODS=$(kubectl get pods -n kube-system -l app=kindnet --no-headers 2>/dev/null | wc -l | tr -d ' ')
CNI_RUNNING=$(kubectl get pods -n kube-system -l app=kindnet --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')

if [ "$CNI_RUNNING" -gt 0 ]; then
    check_pass "CNI networking (kindnet) is running ($CNI_RUNNING/$CNI_PODS pods)"
else
    check_warn "CNI networking may not be properly configured"
fi
echo ""

# 9. Check port mappings
echo "🔍 Checking port mappings..."
EXPECTED_PORTS=(30000 30090 30091)
for port in "${EXPECTED_PORTS[@]}"; do
    if lsof -i ":$port" &>/dev/null || netstat -an 2>/dev/null | grep -q ":$port.*LISTEN"; then
        check_pass "Port $port is mapped and accessible"
    else
        # Port might not be in use yet, which is OK
        echo -e "${BLUE}ℹ️  Port $port mapping configured (not yet in use)${NC}"
    fi
done
echo ""

# 10. Check available resources
echo "🔍 Checking cluster resources..."
# Try to get resource capacity
TOTAL_CPU=$(kubectl get nodes -o json 2>/dev/null | grep -o '"cpu":"[^"]*"' | grep -o '[0-9]*' | awk '{s+=$1} END {print s}')
TOTAL_MEMORY_KB=$(kubectl get nodes -o json 2>/dev/null | grep -o '"memory":"[0-9]*Ki"' | grep -o '[0-9]*' | awk '{s+=$1} END {print s}')
TOTAL_MEMORY_GB=$((TOTAL_MEMORY_KB / 1024 / 1024))

if [ -n "$TOTAL_CPU" ] && [ "$TOTAL_CPU" -gt 0 ]; then
    check_pass "Total CPU: ${TOTAL_CPU} cores"
else
    echo -e "${BLUE}ℹ️  CPU capacity information not available${NC}"
fi

if [ -n "$TOTAL_MEMORY_GB" ] && [ "$TOTAL_MEMORY_GB" -gt 0 ]; then
    if [ "$TOTAL_MEMORY_GB" -ge 6 ]; then
        check_pass "Total Memory: ${TOTAL_MEMORY_GB}GB"
    else
        check_warn "Total Memory: ${TOTAL_MEMORY_GB}GB (workshop needs at least 6GB)"
    fi
else
    echo -e "${BLUE}ℹ️  Memory capacity information not available${NC}"
fi
echo ""

# Summary
echo "=================================================="
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✅ All checks passed!${NC}"
    echo "=================================================="
    echo ""
    echo "Your cluster is ready for the workshop!"
    echo ""
    echo "Next steps:"
    echo "  1. Start with riddles: cd riddles/01-cluster-debugging"
    echo ""
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠️  Verification passed with $WARNINGS warning(s)${NC}"
    echo "=================================================="
    echo ""
    echo "The cluster should work, but check the warnings above."
    echo ""
    exit 0
else
    echo -e "${RED}❌ Verification failed with $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    echo "=================================================="
    echo ""
    echo "Please fix the errors above before proceeding."
    echo "You may need to recreate the cluster: ./setup/install-kind.sh"
    echo ""
    exit 1
fi
