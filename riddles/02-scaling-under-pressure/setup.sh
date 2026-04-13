#!/usr/bin/env bash

# Riddle 2: Scaling Under Pressure - Setup Script
# Deploys services that work fine at low traffic, then hits them with load

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../common/lib.sh
source "$SCRIPT_DIR/../common/lib.sh"

echo "=================================================="
echo "  Riddle 2: Scaling Under Pressure - Setup"
echo "=================================================="
echo ""

# Check kubectl access
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}ERROR: Cannot connect to Kubernetes cluster${NC}"
    echo "Please ensure kubectl is configured correctly."
    exit 1
fi

# --- Prerequisite: OpenCode setup (skills + participant registration) ---
if ! state_done "opencode-configured"; then
    step "Configure OpenCode (MCP + skills)" "$SCRIPT_DIR/../common/setup-opencode.sh"
    state_mark "opencode-configured"
else
    printf "  ${GREEN}[✓]${NC} Configure OpenCode (MCP + skills) ${DIM}(cached)${NC}\n"
fi
echo ""

# Check metrics-server (required for HPA)
if ! kubectl get apiservice v1beta1.metrics.k8s.io &>/dev/null 2>&1; then
    echo -e "${YELLOW}metrics-server is not installed. Installing metrics-server...${NC}"
    "$SCRIPT_DIR/../../setup/install-monitoring.sh"
fi

echo -n "Waiting for metrics-server to be ready..."
for i in $(seq 1 30); do
    if kubectl top nodes &>/dev/null 2>&1; then
        echo -e " ${GREEN}ready${NC}"
        break
    fi
    echo -n "."
    sleep 2
done
if ! kubectl top nodes &>/dev/null 2>&1; then
    echo -e " ${YELLOW}not ready yet (HPA may take a moment to start scaling)${NC}"
fi
echo ""

# Clean up if namespace already exists
if kubectl get namespace riddle-2 &>/dev/null; then
    echo -e "${YELLOW}Namespace 'riddle-2' already exists. Cleaning up...${NC}"
    kubectl delete namespace riddle-2 --wait=true 2>/dev/null || true
    echo "Waiting for cleanup..."
    while kubectl get namespace riddle-2 &>/dev/null; do
        sleep 2
    done
    echo -e "${GREEN}Cleanup complete.${NC}"
    echo ""
fi

# Step 1: Create namespace
echo -e "${BLUE}[1/3]${NC} Creating namespace..."
kubectl apply -f "$SCRIPT_DIR/broken/00-namespace.yaml"
sleep 2

# Step 2: Deploy services
echo -e "${BLUE}[2/3]${NC} Deploying e-commerce services..."
kubectl apply -f "$SCRIPT_DIR/broken/01-workloads.yaml"

echo "  Waiting for services to start..."
kubectl wait --for=condition=ready pod -l tier -n riddle-2 --timeout=90s 2>/dev/null || true
sleep 3

# Step 3: Deploy load generator (starts driving traffic immediately)
echo -e "${BLUE}[3/3]${NC} Deploying load generator..."
kubectl apply -f "$SCRIPT_DIR/broken/02-load-generator.yaml"

echo ""
echo "Waiting for load to ramp up..."
sleep 10

# Write AGENTS.md to auto-load the right skill for this riddle
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cat > "$REPO_ROOT/AGENTS.md" << 'AGENTS_EOF'
# Workshop Instructions

You are helping configure autoscaling for an e-commerce platform in the `riddle-2` namespace that is under heavy load.

**IMPORTANT**: Before starting, load the `k8s-scaling-under-pressure` skill. This skill guides you through configuring HPAs, right-sizing resource requests, and adding resilience to your deployments.

Load it by calling the skill tool with name "k8s-scaling-under-pressure".

The target namespace is `riddle-2`. The services are running but struggling under load — there is no autoscaling configured. A load generator is driving continuous traffic to web-frontend and order-service.
AGENTS_EOF
echo -e "${GREEN}Configured AGENTS.md for Riddle 2 (k8s-scaling-under-pressure skill)${NC}"

echo ""
echo "=================================================="
echo -e "${YELLOW}  Setup Complete - Services Under Load${NC}"
echo "=================================================="
echo ""

echo -e "${BLUE}Current state:${NC}"
echo ""
kubectl get pods -n riddle-2 -o wide 2>/dev/null || true
echo ""
echo -e "${YELLOW}Services are running but the load generator is driving CPU high.${NC}"
echo ""
echo "Your mission: build the scaling and resilience infrastructure that's missing."
echo "There are 5 things to configure — check the lab lesson tab for details."
echo ""
echo "Start by observing the load:"
echo "  kubectl top pods -n riddle-2"
echo ""
echo "Start investigating with OpenCode:"
echo "  opencode"
echo ""
echo -e "${YELLOW}NOTE: If OpenCode is already running, restart it (q then opencode)${NC}"
echo -e "${YELLOW}so it picks up the riddle skill automatically.${NC}"
echo ""
echo "When you think everything is configured:"
echo "  ./verify.sh"
echo ""
