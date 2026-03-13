#!/usr/bin/env bash

# Riddle 2: Autoscaler & Rebalancing - Reset Script

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=================================================="
echo "  Riddle 2: Autoscaler & Rebalancing - Reset"
echo "=================================================="
echo ""

# Delete namespace
if kubectl get namespace riddle-2 &>/dev/null; then
    echo -e "${YELLOW}Deleting namespace 'riddle-2'...${NC}"
    kubectl delete namespace riddle-2 --wait=false

    echo "Waiting for namespace deletion..."
    while kubectl get namespace riddle-2 &>/dev/null; do
        sleep 2
    done
    echo -e "${GREEN}Namespace deleted.${NC}"
else
    echo -e "${YELLOW}Namespace 'riddle-2' not found. Nothing to clean up.${NC}"
fi

echo ""
echo -e "${GREEN}Reset complete!${NC}"
echo ""
echo "To re-run the riddle: ./setup.sh"
echo ""
