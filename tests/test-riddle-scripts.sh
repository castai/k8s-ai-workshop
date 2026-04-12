#!/usr/bin/env bash

# End-to-end tests for riddle setup/verify scripts.
# Requires a running Kubernetes cluster (kind or otherwise).
#
# Usage:
#   ./tests/test-riddle-scripts.sh          # use existing cluster
#   ./tests/test-riddle-scripts.sh --kind   # create+destroy a kind cluster

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$REPO_ROOT/riddles/common/lib.sh"

KIND_MANAGED=false
KIND_CLUSTER="test-riddles"

for arg in "$@"; do
    case "$arg" in
        --kind) KIND_MANAGED=true ;;
    esac
done

cleanup() {
    # Restore patched manifest
    if [ -f "$REPO_ROOT/progress-reconciler/manifests/deployment.yaml.bak" ]; then
        mv "$REPO_ROOT/progress-reconciler/manifests/deployment.yaml.bak" \
           "$REPO_ROOT/progress-reconciler/manifests/deployment.yaml"
    fi
    if [ "$KIND_MANAGED" = true ]; then
        echo ""
        echo -e "${DIM}Cleaning up kind cluster...${NC}"
        kind delete cluster --name "$KIND_CLUSTER" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# --- Setup -----------------------------------------------------------------
echo ""
echo -e "${BOLD}Riddle Script Tests${NC}"
echo ""

if [ "$KIND_MANAGED" = true ]; then
    step "Create kind cluster" bash -c "
        kind delete cluster --name $KIND_CLUSTER 2>/dev/null || true
        kind create cluster --name $KIND_CLUSTER --wait 60s
    "

    step "Build and load progress-reconciler image" bash -c "
        docker build -t ghcr.io/castai/k8s-ai-workshop/progress-reconciler:latest '$REPO_ROOT/progress-reconciler'
        kind load docker-image ghcr.io/castai/k8s-ai-workshop/progress-reconciler:latest --name $KIND_CLUSTER
    "
fi

step "Cluster reachable" kubectl cluster-info

if [ "$KIND_MANAGED" = true ]; then
    # Patch progress-reconciler manifest to use local image (kind loads images locally)
    step "Patch imagePullPolicy for kind" bash -c "
        sed -i.bak 's/imagePullPolicy: Always/imagePullPolicy: IfNotPresent/' '$REPO_ROOT/progress-reconciler/manifests/deployment.yaml'
    "

    # Install metrics-server for riddle 3 (lightweight, avoids full Prometheus stack)
    step "Install metrics-server" bash -c "
        helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ 2>/dev/null || true
        helm repo update metrics-server
        helm install metrics-server metrics-server/metrics-server \
            --namespace kube-system \
            --set args={--kubelet-insecure-tls} \
            --wait --timeout 60s
    "
fi

# --- Riddle 1 --------------------------------------------------------------
echo ""
echo -e "${BOLD}Riddle 1: Cluster Debugging${NC}"
echo ""

step "First run" bash -c "
    cd '$REPO_ROOT' && ./riddles/01-cluster-debugging/setup.sh 2>&1
"

step "Namespace exists" kubectl get namespace riddle-1

step "Idempotency (second run)" bash -c "
    cd '$REPO_ROOT' && ./riddles/01-cluster-debugging/setup.sh 2>&1
"

step "No port-forward PID leak" bash -c '
    PF_COUNT=$(lsof -ti:8080 2>/dev/null | wc -l | tr -d " ")
    if [ "$PF_COUNT" -gt 1 ]; then
        echo "Expected <=1 port-forward PIDs, got $PF_COUNT"
        exit 1
    fi
'

step "Verify script runs without crash" bash -c "
    cd '$REPO_ROOT/riddles/01-cluster-debugging' && ./verify.sh 2>&1 || true
"

# --- Riddle 2 --------------------------------------------------------------
echo ""
echo -e "${BOLD}Riddle 2: Autoscaler & Rebalancing${NC}"
echo ""

step "First run" bash -c "
    cd '$REPO_ROOT' && echo '' | ./riddles/02-autoscaler-rebalancing/setup.sh 2>&1
"

step "Namespace exists" kubectl get namespace riddle-2

step "Idempotency (second run)" bash -c "
    cd '$REPO_ROOT' && echo '' | ./riddles/02-autoscaler-rebalancing/setup.sh 2>&1
"

step "No duplicate CASTAI_API_KEY env vars" bash -c '
    ENV_JSON=$(kubectl get deployment progress-reconciler -n progress-reconciler \
        -o jsonpath="{.spec.template.spec.containers[0].env}" 2>/dev/null || echo "[]")
    DUP_COUNT=$(echo "$ENV_JSON" | grep -o "CASTAI_API_KEY" | wc -l | tr -d " ")
    if [ "$DUP_COUNT" -gt 1 ]; then
        echo "Expected <=1 CASTAI_API_KEY entries, got $DUP_COUNT"
        exit 1
    fi
'

step "Verify script runs without crash" bash -c "
    cd '$REPO_ROOT/riddles/02-autoscaler-rebalancing' && ./verify.sh 2>&1 || true
"

# --- Riddle 3 --------------------------------------------------------------
echo ""
echo -e "${BOLD}Riddle 3: Resource Right-Sizing${NC}"
echo ""

step "First run" bash -c "
    cd '$REPO_ROOT' && ./riddles/03-autoscaling/setup.sh 2>&1
"

step "Namespace exists" kubectl get namespace riddle-3

step "Idempotency (second run)" bash -c "
    cd '$REPO_ROOT' && ./riddles/03-autoscaling/setup.sh 2>&1
"

step "Namespace still exists after re-run" kubectl get namespace riddle-3

step "Verify script runs without crash" bash -c "
    cd '$REPO_ROOT/riddles/03-autoscaling' && ./verify.sh 2>&1 || true
"

# --- Summary ---------------------------------------------------------------
echo ""
echo -e "${GREEN}${BOLD}All tests passed!${NC}"
echo ""
