#!/usr/bin/env bash

# Riddle 3: Resource Right-Sizing - Reset Script

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=================================================="
echo "  Riddle 3: Resource Right-Sizing - Reset"
echo "=================================================="
echo ""

if ! kubectl get namespace riddle-3 &>/dev/null; then
    echo -e "${YELLOW}⚠️  Namespace 'riddle-3' doesn't exist${NC}"
    exit 0
fi

echo "🗑️  Deleting namespace riddle-3..."
kubectl delete namespace riddle-3

echo ""
echo "⏳ Waiting for namespace deletion..."
while kubectl get namespace riddle-3 &>/dev/null; do
    echo -n "."
    sleep 2
done

echo ""
echo ""
echo "=================================================="
echo -e "${GREEN}✅ Reset Complete${NC}"
echo "=================================================="
echo ""
echo "To start the riddle again: ./setup.sh"
echo ""
