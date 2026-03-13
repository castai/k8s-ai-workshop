#!/usr/bin/env bash

# Riddle 2: Autoscaler & Rebalancing - Setup Script
# Deploys over-provisioned microservices that exceed 2-node capacity

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=================================================="
echo "  Riddle 2: Autoscaler & Rebalancing - Setup"
echo "=================================================="
echo ""

# Check kubectl access
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}ERROR: Cannot connect to Kubernetes cluster${NC}"
    echo "Please ensure kubectl is configured correctly."
    exit 1
fi

# Check CAST AI prerequisite
echo -e "${YELLOW}Checking CAST AI prerequisite...${NC}"
echo ""
echo "This riddle requires CAST AI to be fully set up:"
echo "  - CAST AI API key configured in OpenCode"
echo "  - Cluster onboarded to CAST AI console (Phase 1 + Phase 2)"
echo ""
echo "If you haven't set this up yet, press Ctrl+C and follow these steps:"
echo ""
echo -e "  ${YELLOW}1. Create API Key and Configure OpenCode:${NC}"
echo -e "     ${BLUE}$SCRIPT_DIR/../common/setup-opencode.sh --with-castai${NC}"
echo "     (go to https://console.cast.ai -> API Access -> Create User API Key)"
echo ""
echo -e "  ${YELLOW}2. Onboard your cluster to CAST AI console:${NC}"
echo "     - Go to https://console.cast.ai -> Click 'Connect cluster' -> Select EKS"
echo "     - Copy the read-only onboarding script and run it locally, wait for it to complete"
echo "     - Click the green 'Enable CAST AI' button, copy the full onboarding script and run it locally"
echo "     - Wait for it to finish - your cluster should appear in the console"
echo ""
read -p "Press ENTER to continue if CAST AI is fully configured, or Ctrl+C to abort... "

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

# Step 2: Deploy persistent microservices
echo -e "${BLUE}[2/3]${NC} Deploying persistent microservices..."
kubectl apply -f "$SCRIPT_DIR/broken/01-workloads.yaml"

# Step 3: Deploy temporary jobs (heavy, complete after ~60s)
echo -e "${BLUE}[3/3]${NC} Deploying temporary batch jobs (data migration, index rebuild, cache warmup)..."
kubectl apply -f "$SCRIPT_DIR/broken/02-jobs.yaml"

echo ""
echo "Waiting for pods to settle..."
sleep 10

# Step 4: Configure progress-reconciler with CAST AI API key
echo ""
echo -e "${BLUE}[4/4]${NC} Configuring progress-reconciler with CAST AI API key..."
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

if [ -n "$CASTAI_API_KEY" ] && [ "$CASTAI_API_KEY" != "REPLACE_WITH_YOUR_CASTAI_API_KEY" ]; then
    echo -e "${GREEN}✓ Found CAST AI API key in OpenCode config${NC}"

    # Create or update secret in progress-reconciler namespace
    if kubectl get namespace progress-reconciler &>/dev/null; then
        kubectl create secret generic castai-credentials \
            --from-literal=api-key="$CASTAI_API_KEY" \
            -n progress-reconciler \
            --dry-run=client -o yaml | kubectl apply -f -

        echo -e "${GREEN}✓ Updated CAST AI credentials in progress-reconciler namespace${NC}"

        # Patch deployment to add CASTAI_API_KEY environment variable
        kubectl patch deployment progress-reconciler -n progress-reconciler --type=json -p='[
          {
            "op": "add",
            "path": "/spec/template/spec/containers/0/env/-",
            "value": {
              "name": "CASTAI_API_KEY",
              "valueFrom": {
                "secretKeyRef": {
                  "name": "castai-credentials",
                  "key": "api-key",
                  "optional": true
                }
              }
            }
          }
        ]' 2>/dev/null || echo -e "${YELLOW}  (deployment may already have the env var)${NC}"

        echo -e "${GREEN}✓ Configured deployment to use CAST AI credentials${NC}"
        echo -e "${GREEN}✓ Deployment will restart automatically with new configuration${NC}"
    else
        echo -e "${YELLOW}⚠ progress-reconciler namespace not found - skipping credential setup${NC}"
        echo -e "${YELLOW}  Deploy progress-reconciler first, then re-run this setup${NC}"
    fi
else
    echo -e "${YELLOW}⚠ CAST AI API key not found in OpenCode config${NC}"
    echo -e "${YELLOW}  Run: ../common/setup-opencode.sh --with-castai${NC}"
    echo -e "${YELLOW}  Progress reconciler won't be able to verify rebalancing completion${NC}"
fi

# Write AGENTS.md to auto-load the right skill for this riddle
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cat > "$REPO_ROOT/AGENTS.md" << 'AGENTS_EOF'
# Workshop Instructions

You are helping fix a capacity-starved Kubernetes cluster in the `riddle-2` namespace. Pods are stuck in Pending because the cluster doesn't have enough nodes.

**IMPORTANT**: Before starting, load the `k8s-autoscale-rebalance` skill. This skill guides you through using CAST AI to autoscale the cluster, then rebalance after temporary jobs complete.

Load it by calling the skill tool with name "k8s-autoscale-rebalance".

You have two MCP servers: `kubernetes` (kubectl) and `castai` (CAST AI platform). Use both.

The target namespace is `riddle-2`. There are persistent Deployments and temporary batch Jobs. The Jobs complete after ~60 seconds.
AGENTS_EOF
echo -e "${GREEN}Configured AGENTS.md for Riddle 2 (k8s-autoscale-rebalance skill)${NC}"

echo ""
echo "=================================================="
echo -e "${YELLOW}  Setup Complete - Pods are PENDING${NC}"
echo "=================================================="
echo ""

echo -e "${BLUE}Current state:${NC}"
echo ""
kubectl get pods -n riddle-2 -o wide 2>/dev/null || true
echo ""

PENDING=$(kubectl get pods -n riddle-2 --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l | tr -d ' ')
RUNNING=$(kubectl get pods -n riddle-2 --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')

echo -e "${RED}Pending pods: $PENDING${NC}"
echo -e "${GREEN}Running pods: $RUNNING${NC}"
echo ""
echo -e "${YELLOW}The cluster doesn't have enough capacity for all pods.${NC}"
echo -e "${YELLOW}Batch jobs + microservices together need ~24 CPU - way more than 2 nodes can handle.${NC}"
echo ""
echo "Your mission:"
echo "  Step 1: Use OpenCode to enable the autoscaler and fix pending pods"
echo "  Step 2: Wait for batch jobs to complete (~60 seconds after scheduling)"
echo "          The cluster will then have excess nodes with very little running"
echo "  Step 3: Use OpenCode to rebalance the cluster and optimize costs"
echo ""
echo "Start investigating with OpenCode:"
echo "  opencode"
echo ""
echo -e "${YELLOW}NOTE: If OpenCode is already running, restart it (q then opencode)${NC}"
echo -e "${YELLOW}so it picks up the riddle skill automatically.${NC}"
echo ""
echo "Or use kubectl directly:"
echo "  kubectl get pods -n riddle-2"
echo "  kubectl get events -n riddle-2 --field-selector reason=FailedScheduling"
echo ""
echo "When you think everything is fixed:"
echo "  ./verify.sh"
echo ""
