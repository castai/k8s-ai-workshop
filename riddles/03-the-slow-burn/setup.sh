#!/usr/bin/env bash

# Riddle 3: The Slow Burn - Setup Script
# Deploys a workload with insufficient memory limits (will OOMKill)

set -e

RIDDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../common/lib.sh
source "$RIDDLE_DIR/../common/lib.sh"

# External autoscaler is managing the cluster

echo "=================================================="
echo "  Riddle 3: The Slow Burn - Setup"
echo "=================================================="
echo ""

# Check cluster
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}Cannot connect to cluster${NC}"
    exit 1
fi

# Check metrics-server, install if missing
echo "Checking metrics-server..."
if ! kubectl get apiservice v1beta1.metrics.k8s.io &>/dev/null; then
    echo -e "${YELLOW}metrics-server is not installed. Installing monitoring stack...${NC}"
    "$RIDDLE_DIR/../../setup/install-monitoring.sh"
fi

if kubectl top nodes &>/dev/null; then
    echo -e "${GREEN}metrics-server is working${NC}"
else
    echo -e "${YELLOW}metrics-server is installed but may need time to collect metrics${NC}"
fi
echo ""

# Clean up any existing deployments in riddle-3 namespace
if kubectl get namespace riddle-3 &>/dev/null; then
    echo "Cleaning up existing resources in riddle-3..."
    kubectl delete deployment --all -n riddle-3 --ignore-not-found=true 2>/dev/null || true
    kubectl delete pod --all -n riddle-3 --ignore-not-found=true 2>/dev/null || true
    sleep 5
fi
echo ""

# Create namespace and deploy broken workload
echo "Creating namespace riddle-3..."
kubectl apply -f "$RIDDLE_DIR/broken/namespace.yaml"
echo ""

echo "Deploying data processing workload..."
echo ""

kubectl apply -f "$RIDDLE_DIR/broken/workload.yaml"

echo ""
echo "Waiting for pods to start..."
sleep 15

echo ""
echo "Current status:"
kubectl get pods -n riddle-3
echo ""

# Write AGENTS.md to auto-load the right skill for this riddle
REPO_ROOT="$(cd "$RIDDLE_DIR/../.." && pwd)"
cat > "$REPO_ROOT/AGENTS.md" << 'AGENTS_EOF'
# Workshop Instructions

You are helping diagnose and fix a workload in the `riddle-3` namespace that keeps getting OOMKilled.

**IMPORTANT**: Before starting, load the `k8s-resource-rightsizing` skill. This skill guides you through diagnosing OOMKill issues and determining the correct resource configuration.

Load it by calling the skill tool with name "k8s-resource-rightsizing".

The target namespace is `riddle-3`. The `stress-app` deployment has pods that run for ~1 minute then get OOMKilled. The memory limit is set too low for the workload's steady-state usage.
AGENTS_EOF
echo -e "${GREEN}Configured AGENTS.md for Riddle 3 (k8s-resource-rightsizing skill)${NC}"

echo ""
echo "=================================================="
echo -e "${YELLOW}Riddle Setup Complete${NC}"
echo "=================================================="
echo ""
echo "The workload looks healthy... for now."
echo "Watch it for a couple of minutes before touching anything."
echo ""
echo "Your task: figure out what's going wrong and fix it."
echo "  See the README for details: cat README.md"
echo ""
echo "Start with OpenCode:"
echo "  opencode"
echo ""
echo -e "${YELLOW}NOTE: If OpenCode is already running, restart it (q then opencode)${NC}"
echo -e "${YELLOW}so it picks up the riddle skill automatically.${NC}"
echo ""
echo "Or start observing:"
echo "  kubectl get pods -n riddle-3 -w"
echo ""
