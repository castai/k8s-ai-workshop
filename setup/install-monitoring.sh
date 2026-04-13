#!/usr/bin/env bash

# Kubernetes Workshop - metrics-server Installation Script
# Required for kubectl top and HPA (riddles 2 and 3)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=================================================="
echo "  Kubernetes Workshop - metrics-server Setup"
echo "=================================================="
echo ""

# Check if cluster is running
echo "Checking cluster..."
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}Cannot connect to cluster${NC}"
    echo "Please ensure kubectl is configured correctly."
    exit 1
fi
echo -e "${GREEN}Cluster is accessible${NC}"
echo ""

# Check if metrics-server is already working
if kubectl top nodes &>/dev/null 2>&1; then
    echo -e "${GREEN}metrics-server is already installed and working${NC}"
    kubectl top nodes
    exit 0
fi

# Install metrics-server via Helm
echo "Installing metrics-server..."

helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ 2>/dev/null || true
helm repo update metrics-server

# Detect if running on kind (needs --kubelet-insecure-tls)
EXTRA_ARGS=""
if kubectl get nodes -o jsonpath='{.items[0].spec.providerID}' 2>/dev/null | grep -q "kind://"; then
    EXTRA_ARGS="--set args={--kubelet-insecure-tls}"
fi

helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  $EXTRA_ARGS \
  --wait \
  --timeout 5m

echo ""
echo -e "${GREEN}metrics-server installed${NC}"
echo ""

# Wait for metrics to be available
echo -n "Waiting for metrics to be available..."
for i in $(seq 1 12); do
    if kubectl top nodes &>/dev/null 2>&1; then
        echo ""
        echo -e "${GREEN}metrics-server is working${NC}"
        kubectl top nodes
        echo ""
        exit 0
    fi
    echo -n "."
    sleep 5
done

echo ""
echo -e "${YELLOW}metrics-server installed but may need more time to collect metrics${NC}"
echo "  Try again in 30 seconds: kubectl top nodes"
echo ""
