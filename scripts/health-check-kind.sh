#!/usr/bin/env bash

# Workshop Health Check Script
# Comprehensive check of all workshop components

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=================================================="
echo "  Workshop Health Check"
echo "=================================================="
echo ""

ERRORS=0
WARNINGS=0

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

# 1. Check Docker
echo "🐳 Checking Docker..."
if docker info &>/dev/null; then
    check_pass "Docker is running"
    DOCKER_MEM=$(docker info --format '{{.MemTotal}}' 2>/dev/null)
    DOCKER_MEM_GB=$((DOCKER_MEM / 1024 / 1024 / 1024))
    if [ "$DOCKER_MEM_GB" -ge 8 ]; then
        check_pass "Docker has ${DOCKER_MEM_GB}GB memory"
    else
        check_warn "Docker has only ${DOCKER_MEM_GB}GB memory (8GB+ recommended)"
    fi
else
    check_fail "Docker is not running"
    exit 1
fi
echo ""

# 2. Check kind cluster
echo "☸️  Checking kind cluster..."
if kind get clusters 2>/dev/null | grep -q "^workshop-cluster$"; then
    check_pass "Cluster 'workshop-cluster' exists"
else
    check_fail "Cluster 'workshop-cluster' not found"
    echo "   Run: ./setup/install-kind.sh"
    exit 1
fi
echo ""

# 3. Check kubectl connectivity
echo "🔌 Checking kubectl connectivity..."
if kubectl cluster-info &>/dev/null; then
    check_pass "Can connect to cluster"
else
    check_fail "Cannot connect to cluster"
fi

CONTEXT=$(kubectl config current-context 2>/dev/null || echo "")
if [ "$CONTEXT" == "kind-workshop-cluster" ]; then
    check_pass "Context is 'kind-workshop-cluster'"
else
    check_warn "Context is '$CONTEXT' (expected: kind-workshop-cluster)"
fi
echo ""

# 4. Check nodes
echo "🖥️  Checking nodes..."
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready " || true)

if [ "$NODE_COUNT" -eq 4 ]; then
    check_pass "Found 4 nodes"
else
    check_warn "Found $NODE_COUNT nodes (expected: 4)"
fi

if [ "$READY_NODES" -eq "$NODE_COUNT" ]; then
    check_pass "All $NODE_COUNT nodes are Ready"
else
    check_fail "Only $READY_NODES of $NODE_COUNT nodes are Ready"
fi
echo ""

# 5. Check system pods
echo "🔧 Checking system pods..."
SYSTEM_TOTAL=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | wc -l | tr -d ' ')
SYSTEM_RUNNING=$(kubectl get pods -n kube-system --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')

if [ "$SYSTEM_RUNNING" -eq "$SYSTEM_TOTAL" ] && [ "$SYSTEM_TOTAL" -gt 0 ]; then
    check_pass "All $SYSTEM_TOTAL system pods are Running"
else
    check_warn "$SYSTEM_RUNNING of $SYSTEM_TOTAL system pods are Running"
fi
echo ""

# 6. Check metrics-server
echo "📈 Checking metrics-server..."
if kubectl top nodes &>/dev/null; then
    check_pass "metrics-server is working"
else
    check_warn "metrics-server not working (may need time or reinstall)"
fi
echo ""

# 8. Check service accessibility
echo "🌐 Checking service accessibility..."

# Check if any services are exposed
NODEPORT_SVCS=$(kubectl get svc -A -o json 2>/dev/null | jq -r '.items[] | select(.spec.type=="NodePort") | "\(.metadata.namespace)/\(.metadata.name):\(.spec.ports[0].nodePort)"' 2>/dev/null || echo "")

if [ -n "$NODEPORT_SVCS" ]; then
    echo "   NodePort services found:"
    echo "$NODEPORT_SVCS" | while read -r svc; do
        NS=$(echo $svc | cut -d'/' -f1)
        NAME=$(echo $svc | cut -d'/' -f2 | cut -d':' -f1)
        PORT=$(echo $svc | cut -d':' -f2)
        echo "     - $NS/$NAME on port $PORT"

        # Test connectivity
        if curl -s -f -m 2 http://localhost:$PORT >/dev/null 2>&1; then
            check_pass "http://localhost:$PORT is accessible"
        else
            echo -e "     ${YELLOW}⚠️  http://localhost:$PORT not responding (may need pods running)${NC}"
        fi
    done
else
    echo "   No NodePort services exposed yet"
fi
echo ""

# 10. Check active riddles
echo "🎯 Checking active riddles..."
for ns in riddle-1 riddle-2 riddle-3; do
    if kubectl get namespace $ns &>/dev/null; then
        POD_COUNT=$(kubectl get pods -n $ns --no-headers 2>/dev/null | wc -l | tr -d ' ')
        RUNNING=$(kubectl get pods -n $ns --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
        echo "   $ns: $RUNNING/$POD_COUNT pods Running"
    fi
done
echo ""

# Summary
echo "=================================================="
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✅ All checks passed!${NC}"
    echo "=================================================="
    echo ""
    echo "Your workshop environment is healthy and ready!"
    echo ""
    echo "Next steps:"
    echo "  - Start riddles: cd riddles/"
    echo ""
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠️  Checks passed with $WARNINGS warning(s)${NC}"
    echo "=================================================="
    echo ""
    echo "The environment should work, but check warnings above."
    echo ""
    exit 0
else
    echo -e "${RED}❌ Health check failed with $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    echo "=================================================="
    echo ""
    echo "Please fix the errors above before proceeding."
    echo ""
    echo "Common fixes:"
    echo "  - Reinstall cluster: ./setup/install-kind.sh"
    echo "  - Reinstall metrics-server: ./setup/install-monitoring.sh"
    echo "  - Check troubleshooting: cat riddles/common/troubleshooting.md"
    echo ""
    exit 1
fi
