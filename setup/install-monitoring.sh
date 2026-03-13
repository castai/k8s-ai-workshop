#!/usr/bin/env bash

# Kubernetes Workshop - Monitoring Stack Installation Script
# Installs Prometheus, Grafana, and metrics-server

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=================================================="
echo "  Kubernetes Workshop - Monitoring Stack Setup"
echo "=================================================="
echo ""

# Check if cluster is running
echo "🔍 Checking cluster..."
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}❌ Cannot connect to cluster${NC}"
    echo "Please run ./setup/install-kind.sh first"
    exit 1
fi
echo -e "${GREEN}✅ Cluster is accessible${NC}"
echo ""

# Add Helm repositories
echo "📦 Adding Helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ 2>/dev/null || true
helm repo update
echo -e "${GREEN}✅ Helm repositories updated${NC}"
echo ""

# Create monitoring namespace
echo "📁 Creating monitoring namespace..."
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✅ Namespace created${NC}"
echo ""

# Check if monitoring directory exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITORING_DIR="$SCRIPT_DIR/../monitoring"

if [ ! -d "$MONITORING_DIR" ]; then
    echo -e "${YELLOW}⚠️  Monitoring configuration directory not found${NC}"
    echo "Creating directory structure..."
    mkdir -p "$MONITORING_DIR/prometheus"
    mkdir -p "$MONITORING_DIR/grafana/dashboards"
    mkdir -p "$MONITORING_DIR/metrics-server"
fi

# Create Prometheus values file if it doesn't exist
PROMETHEUS_VALUES="$MONITORING_DIR/prometheus/values.yaml"
if [ ! -f "$PROMETHEUS_VALUES" ]; then
    echo "Creating default Prometheus values file..."
    cat > "$PROMETHEUS_VALUES" << 'EOF'
# Prometheus Stack Configuration for Workshop
# Optimized for local kind cluster

# Configure Prometheus
prometheus:
  service:
    type: NodePort
    nodePort: 30090
  prometheusSpec:
    # Resource limits for workshop
    resources:
      requests:
        memory: 400Mi
        cpu: 200m
      limits:
        memory: 800Mi
        cpu: 500m
    # Retention settings
    retention: 6h
    retentionSize: "5GB"
    # Storage
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi
    # Service monitors
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false

# Configure Grafana
grafana:
  enabled: true
  service:
    type: NodePort
    nodePort: 30091
  adminPassword: "admin"
  # Resource limits
  resources:
    requests:
      memory: 128Mi
      cpu: 100m
    limits:
      memory: 256Mi
      cpu: 200m
  # Persistence
  persistence:
    enabled: false  # Disable for workshop to save resources
  # Dashboards
  defaultDashboardsEnabled: true
  defaultDashboardsTimezone: "browser"

# Configure Alertmanager (disabled for workshop)
alertmanager:
  enabled: false

# Configure node-exporter
prometheus-node-exporter:
  resources:
    requests:
      memory: 32Mi
      cpu: 50m
    limits:
      memory: 64Mi
      cpu: 100m

# Configure kube-state-metrics
kube-state-metrics:
  resources:
    requests:
      memory: 64Mi
      cpu: 50m
    limits:
      memory: 128Mi
      cpu: 100m

# Configure prometheus-operator
prometheusOperator:
  resources:
    requests:
      memory: 128Mi
      cpu: 100m
    limits:
      memory: 256Mi
      cpu: 200m
EOF
fi

# Install kube-prometheus-stack
echo "🚀 Installing Prometheus stack..."
echo "   This will take 2-5 minutes..."
echo ""

helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values "$PROMETHEUS_VALUES" \
  --wait \
  --timeout 10m

echo ""
echo -e "${GREEN}✅ Prometheus stack installed${NC}"
echo ""

# Install metrics-server
echo "🚀 Installing metrics-server..."

# Create metrics-server values file for kind
METRICS_VALUES="$MONITORING_DIR/metrics-server/values.yaml"
if [ ! -f "$METRICS_VALUES" ]; then
    echo "Creating metrics-server values file..."
    cat > "$METRICS_VALUES" << 'EOF'
# metrics-server configuration for kind cluster
# Required for kubectl top and HPA

args:
  - --kubelet-insecure-tls
  - --kubelet-preferred-address-types=InternalIP

resources:
  requests:
    memory: 64Mi
    cpu: 50m
  limits:
    memory: 128Mi
    cpu: 100m
EOF
fi

helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --values "$METRICS_VALUES" \
  --wait \
  --timeout 5m

echo ""
echo -e "${GREEN}✅ metrics-server installed${NC}"
echo ""

# Wait for pods to be ready
echo "⏳ Waiting for monitoring pods to be ready..."
kubectl wait --for=condition=ready pod -l "app.kubernetes.io/name=prometheus" -n monitoring --timeout=180s 2>/dev/null || true
kubectl wait --for=condition=ready pod -l "app.kubernetes.io/name=grafana" -n monitoring --timeout=180s 2>/dev/null || true
kubectl wait --for=condition=ready pod -l "app.kubernetes.io/name=metrics-server" -n kube-system --timeout=180s 2>/dev/null || true

echo ""
echo "📊 Monitoring stack status:"
kubectl get pods -n monitoring
echo ""

# Test metrics-server
echo "🧪 Testing metrics-server..."
sleep 10  # Give metrics-server time to collect initial metrics
if kubectl top nodes &>/dev/null; then
    echo -e "${GREEN}✅ metrics-server is working${NC}"
    kubectl top nodes
else
    echo -e "${YELLOW}⚠️  metrics-server may need more time to start collecting metrics${NC}"
    echo "   Try again in 30 seconds: kubectl top nodes"
fi
echo ""

# Get service URLs
PROMETHEUS_PORT=$(kubectl get svc -n monitoring prometheus-kube-prometheus-prometheus -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "30090")
GRAFANA_PORT=$(kubectl get svc -n monitoring prometheus-grafana -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "30091")

echo "=================================================="
echo -e "${GREEN}✅ Monitoring stack installation complete!${NC}"
echo "=================================================="
echo ""
echo "Access monitoring services:"
echo ""
echo "  📊 Prometheus:"
echo "     URL: http://localhost:${PROMETHEUS_PORT}"
echo "     Query metrics and view targets"
echo ""
echo "  📈 Grafana:"
echo "     URL: http://localhost:${GRAFANA_PORT}"
echo "     Username: admin"
echo "     Password: admin"
echo "     Pre-built dashboards available!"
echo ""
echo "  📏 metrics-server:"
echo "     Test with: kubectl top nodes"
echo "                kubectl top pods -A"
echo ""
echo "Useful commands:"
echo "  kubectl get all -n monitoring"
echo "  kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus"
echo "  kubectl logs -n monitoring -l app.kubernetes.io/name=grafana"
echo ""
echo "Next steps:"
echo "  1. Open Grafana and explore dashboards"
echo "  2. Start with riddles: cd riddles/01-cluster-debugging"
echo ""
