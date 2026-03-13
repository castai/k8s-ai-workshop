#!/usr/bin/env bash

# Riddle 1: Advanced Cluster Debugging - Reset Script
# Cleans up all resources including node taints and labels

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=================================================="
echo "  Riddle 1: Cluster Debugging - Reset"
echo "=================================================="
echo ""

# Step 1: Remove node taint and label from ALL nodes
echo -e "${YELLOW}Removing node taints and labels...${NC}"
for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
    kubectl taint nodes "$node" processing=dedicated:NoSchedule- 2>/dev/null || true
    kubectl label nodes "$node" workload-type- 2>/dev/null || true
done
echo -e "${GREEN}Node configuration cleaned.${NC}"

# Step 2: Delete namespace
if kubectl get namespace riddle-1 &>/dev/null; then
    echo ""
    echo -e "${YELLOW}Deleting namespace 'riddle-1'...${NC}"
    kubectl delete namespace riddle-1 --wait=false

    echo "Waiting for namespace deletion..."
    while kubectl get namespace riddle-1 &>/dev/null; do
        sleep 2
    done
    echo -e "${GREEN}Namespace deleted.${NC}"
else
    echo -e "${YELLOW}Namespace 'riddle-1' not found. Nothing to clean up.${NC}"
fi

echo ""
echo -e "${GREEN}Reset complete!${NC}"
echo ""
echo "=================================================="
echo -e "${YELLOW}  BEFORE STARTING RIDDLE 2 - SETUP CAST AI${NC}"
echo "=================================================="
echo ""
echo "Riddle 2 requires CAST AI. Complete these steps now:"
echo ""
echo -e "  ${YELLOW}Step 1: Create API Key and Configure OpenCode${NC}"
echo ""
echo "  Run the setup script (it will prompt for your CAST AI API key):"
echo -e "     ${BLUE}../common/setup-opencode.sh --with-castai${NC}"
echo ""
echo "  To get an API key:"
echo "    - Go to https://console.cast.ai and sign up / log in"
echo "    - Navigate to the API Access section"
echo "    - Create a new User API Key"
echo "    - Copy and paste it into the script prompt"
echo ""
echo -e "  ${YELLOW}Step 2: Onboard Your Cluster to CAST AI Console${NC}"
echo ""
echo "  Read-only onboarding:"
echo "    - Go to https://console.cast.ai"
echo "    - Click 'Connect cluster' -> Select EKS as the provider"
echo "    - Copy the provided script and run it locally"
echo "    - Wait for the script to complete"
echo ""
echo "  Full onboarding:"
echo "    - Click the green 'Enable CAST AI' button in the console UI"
echo "    - Copy the provided script and run it locally"
echo "    - Wait for it to finish"
echo ""
echo -e "  ${YELLOW}Step 3: Verify${NC}"
echo ""
echo "  1. Run: opencode"
echo "  2. Ask: \"Can you access my CAST AI account?\""
echo ""
echo "Once verified, start Riddle 2:"
echo "  cd ../02-autoscaler-rebalancing"
echo "  ./setup.sh"
echo ""
