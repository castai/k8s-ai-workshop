#!/usr/bin/env bash

# Riddle 1: Advanced Cluster Debugging - Setup Script
# Deploys a broken microservices architecture with 5 interconnected issues
# Usage: ./setup.sh [--kind]  (--kind creates a kind cluster, disabled by default)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../common/lib.sh
source "$SCRIPT_DIR/../common/lib.sh"

# Parse flags
SETUP_KIND=false
for arg in "$@"; do
    case "$arg" in
        --kind) SETUP_KIND=true ;;
    esac
done

echo "=================================================="
echo "  Riddle 1: Advanced Cluster Debugging - Setup"
echo "=================================================="
echo ""

# If running as root (e.g. via sudo), use the invoking user's kubeconfig
if [ "$(id -u)" = "0" ] && [ ! -f "${KUBECONFIG:-/root/.kube/config}" ]; then
    if [ -n "$SUDO_USER" ]; then
        SUDO_USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        export KUBECONFIG="$SUDO_USER_HOME/.kube/config"
    elif [ -f /home/ubuntu/.kube/config ]; then
        export KUBECONFIG="/home/ubuntu/.kube/config"
    fi
fi

# --- Optional: Kind cluster setup ---
if [ "$SETUP_KIND" = true ]; then
    echo -e "${BLUE}Setting up kind cluster...${NC}"
    if ! command -v kind &>/dev/null; then
        echo -e "${RED}ERROR: 'kind' is not installed.${NC}"
        echo "Install it from https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
        exit 1
    fi
    kind create cluster --name riddle-1 2>/dev/null || echo -e "${YELLOW}Kind cluster 'riddle-1' already exists, reusing.${NC}"
    kubectl cluster-info --context kind-riddle-1 &>/dev/null
    echo -e "${GREEN}Kind cluster ready.${NC}"
    echo ""
fi

# Check kubectl access
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}ERROR: Cannot connect to Kubernetes cluster${NC}"
    echo "Please ensure kubectl is configured correctly."
    echo "Tip: pass --kind to create a local kind cluster."
    exit 1
fi

# --- Deploy Progress Reconciler ---
# Non-fatal: riddle scenario should deploy even if the reconciler fails
echo -e "${BLUE}Deploying Progress Reconciler...${NC}"
if ! "$SCRIPT_DIR/../../progress-reconciler/deploy.sh"; then
    echo -e "${YELLOW}⚠ Progress reconciler deployment failed (dashboard tracking may not work)${NC}"
    echo -e "${YELLOW}  The riddle will still work — you can retry the reconciler later.${NC}"
fi
echo ""

# Clean up if namespace already exists
if kubectl get namespace riddle-1 &>/dev/null; then
    echo -e "${YELLOW}Namespace 'riddle-1' already exists. Cleaning up...${NC}"
    # Remove node taints/labels first
    for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
        kubectl taint nodes "$node" processing=dedicated:NoSchedule- 2>/dev/null || true
        kubectl label nodes "$node" workload-type- 2>/dev/null || true
    done
    kubectl delete namespace riddle-1 --wait=true 2>/dev/null || true
    echo "Waiting for cleanup..."
    while kubectl get namespace riddle-1 &>/dev/null; do
        sleep 2
    done
    echo -e "${GREEN}Cleanup complete.${NC}"
    echo ""
fi

# Step 1: Create namespace with ResourceQuota
echo -e "${BLUE}[1/7]${NC} Creating namespace with resource constraints..."
kubectl apply -f "$SCRIPT_DIR/broken/00-namespace-and-quota.yaml"
sleep 2

# Step 2: Deploy infrastructure (filler) services first — these consume quota
echo -e "${BLUE}[2/7]${NC} Deploying infrastructure services..."
kubectl apply -f "$SCRIPT_DIR/broken/01-filler-services.yaml"

echo "  Waiting for infrastructure pods to start..."
kubectl wait --for=condition=ready pod -l tier=infrastructure -n riddle-1 --timeout=60s 2>/dev/null || true
sleep 3

# Step 3: Deploy api-gateway early so the dashboard UI is available
echo -e "${BLUE}[3/7]${NC} Deploying API gateway..."
kubectl apply -f "$SCRIPT_DIR/broken/02-api-gateway.yaml"

echo "  Waiting for api-gateway pods to start..."
kubectl wait --for=condition=ready pod -l app=api-gateway -n riddle-1 --timeout=90s 2>/dev/null || true
sleep 3

# Start port-forwarding now that api-gateway is running
# Kill any existing port-forward on 8080 to avoid PID leaks on re-run
if lsof -ti:8080 &>/dev/null; then
    kill $(lsof -ti:8080) 2>/dev/null || true
    sleep 1
fi
echo -e "${BLUE}Starting port-forward to api-gateway on localhost:8080...${NC}"
nohup kubectl port-forward svc/api-gateway -n riddle-1 --address 0.0.0.0 8080:80 &>/dev/null &
PORT_FWD_PID=$!
echo -e "${GREEN}Port-forward running (PID: $PORT_FWD_PID)${NC}"

# Step 4: Configure node for payment-processor
echo -e "${BLUE}[4/7]${NC} Configuring dedicated processing node..."
# Pick the first node
TARGET_NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')

# Apply taint and label
kubectl taint nodes "$TARGET_NODE" processing=dedicated:NoSchedule --overwrite 2>/dev/null || true
kubectl label nodes "$TARGET_NODE" workload-type=processing --overwrite 2>/dev/null || true
echo "  Node '$TARGET_NODE' configured"

# Step 5: Deploy backend services (these consume remaining quota)
echo -e "${BLUE}[5/7]${NC} Deploying backend services..."
kubectl apply -f "$SCRIPT_DIR/broken/03-payment-processor.yaml"
kubectl apply -f "$SCRIPT_DIR/broken/04-order-service.yaml"
kubectl apply -f "$SCRIPT_DIR/broken/05-inventory-service.yaml"
kubectl apply -f "$SCRIPT_DIR/broken/06-notification-service.yaml"
kubectl apply -f "$SCRIPT_DIR/broken/08-search-service.yaml"
kubectl apply -f "$SCRIPT_DIR/broken/09-recommendation-service.yaml"
sleep 3

# Step 6: Deploy analytics-service last (will be blocked by quota)
echo -e "${BLUE}[6/7]${NC} Deploying analytics service..."
kubectl apply -f "$SCRIPT_DIR/broken/10-analytics-service.yaml"

# Step 7: Deploy miscellaneous resources
echo -e "${BLUE}[7/7]${NC} Deploying additional resources..."
kubectl apply -f "$SCRIPT_DIR/broken/07-red-herrings.yaml"

echo ""
echo "Waiting for pods to settle..."
sleep 10

# Write AGENTS.md to auto-load the right skill for this riddle
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cat > "$REPO_ROOT/AGENTS.md" << 'AGENTS_EOF'
# Workshop Instructions

You are helping debug a broken Kubernetes cluster in the `riddle-1` namespace.

**IMPORTANT**: Before starting, load the `k8s-cluster-debug` skill. This skill contains a structured debugging methodology for systematically finding and fixing all issues in the cluster.

Load it by calling the skill tool with name "k8s-cluster-debug".

The target namespace is `riddle-1`. There are multiple interconnected issues — follow the skill's methodology to fix them in the right order.
AGENTS_EOF
echo -e "${GREEN}Configured AGENTS.md for Riddle 1 (k8s-cluster-debug skill)${NC}"

echo ""
echo "=================================================="
echo -e "${YELLOW}  Setup Complete - System is BROKEN${NC}"
echo "=================================================="
echo ""
echo -e "${BLUE}Current state:${NC}"
echo ""
kubectl get pods -n riddle-1 -o wide
echo ""
echo -e "${YELLOW}Multiple services are failing. Your mission: find and fix all issues.${NC}"
echo ""
echo -e "${GREEN}Open the UI to start investigating:${NC}"
echo ""
echo -e "  ${BLUE}http://localhost:30001${NC}"
echo ""
echo "Start investigating with OpenCode:"
echo "  opencode"
echo ""
echo -e "${YELLOW}NOTE: If OpenCode is already running, restart it (q then opencode)${NC}"
echo -e "${YELLOW}so it picks up the riddle skill automatically.${NC}"
echo ""
echo "  Then ask: 'help me fix the cluster issues'"
echo ""
echo "Or use kubectl directly:"
echo "  kubectl get pods -n riddle-1"
echo "  kubectl get events -n riddle-1 --sort-by='.lastTimestamp'"
echo ""
echo "When you think everything is fixed:"
echo "  ./verify.sh"
echo ""
