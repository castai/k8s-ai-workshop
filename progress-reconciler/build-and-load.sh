#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="progress-reconciler:latest"
CLUSTER_NAME="workshop-cluster"

echo "🔨 Building progress-reconciler image..."
docker build -t "$IMAGE_NAME" "$SCRIPT_DIR"

echo "📦 Loading image into kind cluster..."
kind load docker-image "$IMAGE_NAME" --name "$CLUSTER_NAME"

echo "✅ Image ready: $IMAGE_NAME"