#!/usr/bin/env bash

# Kubernetes Workshop - kind Cluster Installation Script
# This script checks prerequisites and creates a multi-node kind cluster

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=================================================="
echo "  Kubernetes Workshop - kind Cluster Setup"
echo "=================================================="
echo ""

# Check if Docker is installed and running
echo "📦 Checking Docker..."
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker is not installed${NC}"
    echo "Please install Docker Desktop from: https://www.docker.com/products/docker-desktop"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo -e "${RED}❌ Docker daemon is not running${NC}"
    echo "Please start Docker Desktop"
    exit 1
fi

echo -e "${GREEN}✅ Docker is installed and running${NC}"
echo ""

# Check Docker resources
echo "🔍 Checking Docker resources..."
docker_mem=$(docker info --format '{{.MemTotal}}')
docker_mem_gb=$((docker_mem / 1024 / 1024 / 1024))

if [ "$docker_mem_gb" -lt 6 ]; then
    echo -e "${YELLOW}⚠️  Warning: Docker has ${docker_mem_gb}GB memory allocated${NC}"
    echo "   Recommended: At least 8GB (16GB preferred)"
    echo "   The workshop may not run smoothly with less than 8GB"
    echo ""
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    echo -e "${GREEN}✅ Docker has ${docker_mem_gb}GB memory allocated${NC}"
fi
echo ""

# Check if kubectl is installed
echo "⚙️  Checking kubectl..."
if ! command -v kubectl &> /dev/null; then
    echo -e "${YELLOW}⚠️  kubectl is not installed${NC}"
    echo "Installing kubectl..."

    # Detect OS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
            brew install kubectl
        else
            echo "Please install kubectl manually from: https://kubernetes.io/docs/tasks/tools/"
            exit 1
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        chmod +x kubectl
        sudo mv kubectl /usr/local/bin/
    else
        echo "Please install kubectl manually from: https://kubernetes.io/docs/tasks/tools/"
        exit 1
    fi
fi

echo -e "${GREEN}✅ kubectl $(kubectl version --client --short 2>/dev/null | head -n1)${NC}"
echo ""

# Check if kind is installed
echo "🔧 Checking kind..."
if ! command -v kind &> /dev/null; then
    echo -e "${YELLOW}⚠️  kind is not installed${NC}"
    echo "Installing kind..."

    # Detect OS and architecture
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
            brew install kind
        else
            # Manual installation
            if [[ $(uname -m) == "arm64" ]]; then
                curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-darwin-arm64
            else
                curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-darwin-amd64
            fi
            chmod +x ./kind
            sudo mv ./kind /usr/local/bin/kind
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64
        chmod +x ./kind
        sudo mv ./kind /usr/local/bin/kind
    else
        echo "Please install kind manually from: https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
        exit 1
    fi
fi

echo -e "${GREEN}✅ kind $(kind version 2>/dev/null | head -n1)${NC}"
echo ""

# Check if Helm is installed
echo "🎯 Checking Helm..."
if ! command -v helm &> /dev/null; then
    echo -e "${YELLOW}⚠️  Helm is not installed${NC}"
    echo "Installing Helm..."

    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &> /dev/null; then
            brew install helm
        else
            curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
        fi
    else
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi
fi

echo -e "${GREEN}✅ Helm $(helm version --short)${NC}"
echo ""

# Check if cluster already exists
echo "🔍 Checking for existing cluster..."
if kind get clusters 2>/dev/null | grep -q "^workshop-cluster$"; then
    echo -e "${YELLOW}⚠️  Cluster 'workshop-cluster' already exists${NC}"
    read -p "Delete and recreate? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Deleting existing cluster..."
        kind delete cluster --name workshop-cluster
    else
        echo "Using existing cluster"
        exit 0
    fi
fi
echo ""

# Create kind cluster
echo "🚀 Creating kind cluster..."
echo "   This will take 2-5 minutes..."
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/kind-cluster-config.yaml"

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}❌ Configuration file not found: $CONFIG_FILE${NC}"
    exit 1
fi

kind create cluster --config "$CONFIG_FILE"

echo ""
echo -e "${GREEN}✅ Cluster created successfully!${NC}"
echo ""

# Verify cluster
echo "🔍 Verifying cluster..."
kubectl cluster-info --context kind-workshop-cluster
echo ""

# Wait for nodes to be ready
echo "⏳ Waiting for nodes to be ready..."
kubectl wait --for=condition=ready nodes --all --timeout=120s

echo ""
echo "📊 Cluster status:"
kubectl get nodes -o wide
echo ""

echo "=================================================="
echo -e "${GREEN}✅ Setup complete!${NC}"
echo "=================================================="
echo ""
echo "Next steps:"
echo "  1. Run: ./setup/verify-setup.sh"
echo "  2. Run: ./setup/install-monitoring.sh  (metrics-server, auto-installed by riddles 2/3)"
echo ""
echo "Cluster info:"
echo "  Name: workshop-cluster"
echo "  Nodes: 4 (1 control-plane + 3 workers)"
echo "  Context: kind-workshop-cluster"
echo ""
