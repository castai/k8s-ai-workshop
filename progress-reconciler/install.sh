#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "================================================"
echo "  Progress Reconciler - Installation"
echo "================================================"
echo ""

# Build and load image
echo "📦 Building and loading Docker image..."
"$SCRIPT_DIR/build-and-load.sh"
echo ""

# Apply manifests
echo "☸️  Applying Kubernetes manifests..."
kubectl apply -f "$SCRIPT_DIR/manifests/namespace.yaml"
kubectl apply -f "$SCRIPT_DIR/manifests/rbac.yaml"
kubectl apply -f "$SCRIPT_DIR/manifests/config.yaml"
kubectl apply -f "$SCRIPT_DIR/manifests/deployment.yaml"
echo ""

# Wait for deployment
echo "⏳ Waiting for reconciler to be ready..."
kubectl wait --for=condition=available --timeout=60s \
  deployment/progress-reconciler -n progress-reconciler
echo ""

# Show status
echo "================================================"
echo "  ✅ Progress Reconciler installed successfully!"
echo "================================================"
echo ""
kubectl get pods -n progress-reconciler
echo ""
echo "📝 View logs:"
echo "  kubectl logs -f -n progress-reconciler -l app=progress-reconciler"
echo ""
echo "🔍 Check status:"
echo "  kubectl port-forward -n progress-reconciler svc/progress-reconciler 8080:8080"
echo "  curl http://localhost:8080/status"
echo ""