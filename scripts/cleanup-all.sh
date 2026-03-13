#!/usr/bin/env bash

# Complete Workshop Cleanup Script
# Deletes the kind cluster and cleans up Docker resources

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=================================================="
echo "  Workshop Complete Cleanup"
echo "=================================================="
echo ""

echo -e "${YELLOW}⚠️  This will delete the entire workshop cluster and clean up Docker.${NC}"
echo ""
read -p "Are you sure? (yes/no): " -r
if [[ ! $REPLY =~ ^yes$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""

echo "🗑️  Deleting kind cluster..."
if kind get clusters 2>/dev/null | grep -q "^workshop-cluster$"; then
    kind delete cluster --name workshop-cluster
    echo -e "${GREEN}✅ Cluster deleted${NC}"
else
    echo "Cluster 'workshop-cluster' not found"
fi

echo ""
echo "🧹 Cleaning up Docker containers..."
docker container prune -f

echo ""
echo "🧹 Cleaning up Docker volumes..."
docker volume prune -f

echo ""
echo "💾 Docker disk usage:"
docker system df

echo ""
read -p "Clean up unused Docker images? This will free space but slow down next setup. (yes/no): " -r
if [[ $REPLY =~ ^yes$ ]]; then
    echo "🧹 Cleaning up Docker images..."
    docker image prune -a -f
fi

echo ""
echo "=================================================="
echo -e "${GREEN}✅ Cleanup Complete${NC}"
echo "=================================================="
echo ""
echo "Workshop resources have been removed."
echo ""
echo "To set up the workshop again:"
echo "  ./setup/install-kind.sh"
echo ""
