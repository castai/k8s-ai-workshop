#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/manifests"
IMAGE="ghcr.io/castai/k8s-ai-workshop/progress-reconciler:latest"

echo "🚀 Deploying Progress Reconciler..."
echo ""

# Detect kind cluster and build/load image locally if needed
CLUSTER_NAME=$(kubectl config current-context 2>/dev/null | sed -n 's/^kind-//p')
if [ -n "$CLUSTER_NAME" ]; then
    echo "📦 Detected kind cluster '$CLUSTER_NAME' — building image locally..."
    docker build -q -t "$IMAGE" "$SCRIPT_DIR" >/dev/null 2>&1
    kind load docker-image "$IMAGE" --name "$CLUSTER_NAME" 2>/dev/null
    echo "   ✓ Image loaded into kind"
    echo ""
fi

# Apply manifests in order
echo "📦 Creating namespace..."
kubectl apply -f "${MANIFESTS_DIR}/namespace.yaml"

echo "🔐 Setting up RBAC..."
kubectl apply -f "${MANIFESTS_DIR}/rbac.yaml"

echo "⚙️  Creating ConfigMap..."
if [ -f "${MANIFESTS_DIR}/config.yaml" ]; then
    kubectl apply -f "${MANIFESTS_DIR}/config.yaml"
else
    echo "   ⚠️  No config.yaml found, will use defaults"
fi

echo "🎯 Deploying reconciler..."
kubectl apply -f "${MANIFESTS_DIR}/deployment.yaml"

echo ""
echo "⏳ Waiting for deployment to be ready..."
kubectl wait --for=condition=available --timeout=90s \
    deployment/progress-reconciler -n progress-reconciler

echo ""
echo "✅ Progress Reconciler deployed successfully!"
echo ""
echo "📊 Status:"
kubectl get pods -n progress-reconciler
echo ""
echo "📝 View logs:"
echo "   kubectl logs -f -n progress-reconciler deployment/progress-reconciler"
echo ""
echo "🏥 Health check:"
echo "   kubectl port-forward -n progress-reconciler deployment/progress-reconciler 8080:8080"
echo "   curl http://localhost:8080/health"
