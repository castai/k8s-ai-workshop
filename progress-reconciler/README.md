# Progress Reconciler

Kubernetes reconciler that monitors workshop riddle progress and reports to Supabase backend.

## Overview

The Progress Reconciler continuously monitors three workshop riddles, running verification checks every 30 seconds and reporting status changes to the Supabase API.

### Monitored Riddles

| Riddle | Namespace | Riddle ID | Checks |
|----------|-----------|-----------|--------|
| Cluster Debugging | `riddle-1` | `2eecc00a-79a6-4d8e-92a3-06440b5d08c2` | 6 |
| Autoscaler & Rebalancing | `riddle-2` | `24e96064-68d7-4bf9-b222-af29fe2306be` | 5 |
| Resource Right-Sizing | `riddle-3` | `7d7c5ea7-9b3d-4890-ac40-c79b8f30c778` | 5 |

### Status Values

- `not_started`: Namespace exists but 0 checks passed
- `in_progress`: Some checks passed (1 to N-1)
- `completed`: All checks passed (N/N)

## Installation

### Prerequisites

- Kubernetes cluster (kind recommended)
- `kubectl` configured

### Quick Deploy (Recommended for Workshop Participants)

Deploy from GitHub Container Registry (no local build required):

```bash
cd progress-reconciler
./deploy.sh
```

This will:
1. Create progress-reconciler namespace
2. Set up RBAC permissions
3. Deploy from `ghcr.io/narunas-k/progress-reconciler:latest`
4. Wait for pod to be ready
5. Display pod status and helpful commands

### Local Development Install

Build and deploy locally (requires Docker):

```bash
cd progress-reconciler
./install.sh
```

This will:
1. Build Docker image locally
2. Load image into kind cluster
3. Apply Kubernetes manifests
4. Wait for pod to be ready

### Manual Installation

```bash
# Option 1: Deploy from remote image (recommended)
kubectl apply -f manifests/namespace.yaml
kubectl apply -f manifests/rbac.yaml
kubectl apply -f manifests/config.yaml
kubectl apply -f manifests/deployment.yaml

# Option 2: Build and load image locally
./build-and-load.sh
kubectl apply -f manifests/namespace.yaml
kubectl apply -f manifests/rbac.yaml
kubectl apply -f manifests/config.yaml
kubectl apply -f manifests/deployment.yaml

# Wait for ready
kubectl wait --for=condition=available --timeout=60s \
  deployment/progress-reconciler -n progress-reconciler
```

## Usage

### View Logs

```bash
kubectl logs -f -n progress-reconciler -l app=progress-reconciler
```

**Expected log output:**
```
🚀 Starting Progress Reconciler...
🆔 Cluster UID: ca9988ee-f7fe-4be6-a5fe-04314304553b
✅ Configuration loaded from ConfigMap: 3 riddles configured
✅ Reported cluster connection: cluster_uid=ca9988ee-f7fe-4be6-a5fe-04314304553b
🏥 Starting health server on :8080
🔄 Reconciliation loop started (interval: 30s)
✅ Progress Reconciler started successfully
```

When riddles are deployed:
```
🔍 Detected new riddle: riddle-1 (2eecc00a-79a6-4d8e-92a3-06440b5d08c2)
📊 State changed for 2eecc00a-79a6-4d8e-92a3-06440b5d08c2: status not_started→in_progress, checks 0/6→3/6
✅ Reported progress: riddle_id=2eecc00a-79a6-4d8e-92a3-06440b5d08c2, status=in_progress, checks=3/6
```

### Check Status Endpoint

```bash
kubectl port-forward -n progress-reconciler svc/progress-reconciler 8080:8080 &
curl http://localhost:8080/status
```

**Response:**
```json
{
  "timestamp": "2026-03-02T14:00:00Z",
  "riddles": {
    "2eecc00a-79a6-4d8e-92a3-06440b5d08c2": {
      "RiddleID": "2eecc00a-79a6-4d8e-92a3-06440b5d08c2",
      "Namespace": "riddle-1",
      "LastStatus": "in_progress",
      "ChecksPassed": 3,
      "TotalChecks": 6,
      "LastReportTime": "2026-03-02T13:55:00Z",
      "FirstSeenTime": "2026-03-02T13:50:00Z"
    }
  }
}
```

### Health Check Endpoints

- `GET /health` - Liveness probe (returns "OK")
- `GET /ready` - Readiness probe (returns "Ready")
- `GET /status` - Current riddle states (JSON)

## Configuration

Configuration is loaded from ConfigMap `progress-reconciler-config` in the `progress-reconciler` namespace.

### Edit Configuration

```bash
kubectl edit configmap progress-reconciler-config -n progress-reconciler
```

### Configuration Options

```yaml
reconciliation_interval: 30s          # How often to check riddles
report_min_interval: 15s              # Min time between reports per riddle
startup_grace_period: 30s             # Wait after namespace creation
supabase_url: "https://..."           # Supabase API endpoint
retry_max_attempts: 3                 # HTTP retry attempts
retry_backoff_initial: 1s             # Initial retry backoff

riddles:
  - riddle_id: "uuid"
    namespace: "riddle-1"
    enabled: true
    total_checks: 6
```

**Note:** Changes to ConfigMap currently require pod restart. Hot-reload support planned.

## Reporting API

### Initial Connection Report

Sent immediately on startup:
```json
POST https://hsnxzbyedgzepraxwpar.supabase.co/functions/v1/report-progress
{
  "cluster_uid": "ca9988ee-f7fe-4be6-a5fe-04314304553b",
  "cluster_connected": true,
  "timestamp": "2026-03-02T13:00:00Z"
}
```

### Progress Reports

Sent when riddle state changes:
```json
POST https://hsnxzbyedgzepraxwpar.supabase.co/functions/v1/report-progress
{
  "cluster_uid": "ca9988ee-f7fe-4be6-a5fe-04314304553b",
  "riddle_id": "2eecc00a-79a6-4d8e-92a3-06440b5d08c2",
  "status": "in_progress",
  "checks_passed": 3,
  "total_checks": 6,
  "timestamp": "2026-03-02T13:05:00Z"
}
```

## Verification Checks

### Riddle 1: Cluster Debugging (6 checks)

1. ✅ All pods Running (minimum 5 pods)
2. ✅ All pods Ready (N/N containers)
3. ✅ No excessive restarts (≤2 restarts)
4. ✅ All services have endpoints
5. ✅ Frontend accessible at http://localhost:30001
6. ✅ No error events (≤5 warnings)

### Riddle 2: Autoscaler & Rebalancing (5 checks)

1. ✅ All deployments have desired replicas ready
2. ✅ No pods in Pending state
3. ✅ No pods in error states (CrashLoopBackOff, ImagePullBackOff, etc.)
4. ✅ All deployment pods fully Ready (N/N containers ready)
5. ✅ CAST AI rebalancing completed (checks for finished rebalancing plans via API)

### Riddle 3: Resource Right-Sizing (5 checks)

1. ✅ No pods in OOMKilled state
2. ✅ All pods Running and Ready (N/N containers ready)
3. ✅ No recent OOMKill terminations (lastState.terminated.reason)
4. ✅ Memory request >= 120Mi (checked from actual pod spec, not deployment)
5. ✅ WOOP applied recommendations (CAST AI annotations present)

## Testing

### Test with Riddle 1

```bash
# Deploy broken riddle
cd ../riddles/01-cluster-debugging
./setup.sh

# Watch reconciler logs
kubectl logs -f -n progress-reconciler -l app=progress-reconciler

# Expected: Detects riddle, reports in_progress with 0/6 checks

# Fix issues
kubectl apply -f fixed/

# Expected: Reports progress as checks pass (3/6, 6/6), status changes to completed
```

### Test Restart Recovery

```bash
# Delete pod
kubectl delete pod -n progress-reconciler -l app=progress-reconciler

# Watch new pod start
kubectl logs -f -n progress-reconciler -l app=progress-reconciler

# Expected: Reconstructs state, continues reporting without data loss
```

## Troubleshooting

### Pod Not Starting

```bash
# Check pod status
kubectl get pods -n progress-reconciler

# Check events
kubectl get events -n progress-reconciler --sort-by='.lastTimestamp'

# Check logs
kubectl logs -n progress-reconciler -l app=progress-reconciler
```

### Reports Not Sending

```bash
# Check logs for HTTP errors
kubectl logs -n progress-reconciler -l app=progress-reconciler | grep "❌"

# Test Supabase endpoint
curl -X POST https://hsnxzbyedgzepraxwpar.supabase.co/functions/v1/report-progress \
  -H "Content-Type: application/json" \
  -d '{"cluster_uid":"test","cluster_connected":true,"timestamp":"2026-03-02T14:00:00Z"}'
```

### Checks Not Passing

```bash
# Check RBAC permissions
kubectl auth can-i get pods --as=system:serviceaccount:progress-reconciler:progress-reconciler -n riddle-1

# Check if verifier can access resources
kubectl get pods -n riddle-1
kubectl get services -n riddle-1
kubectl get endpoints -n riddle-1
```

## Cleanup

```bash
kubectl delete namespace progress-reconciler
```

## Architecture

```
┌─────────────────────────────────────┐
│  Progress Reconciler Pod            │
│                                      │
│  ┌────────────────────────────────┐ │
│  │  Main Loop (30s interval)      │ │
│  │  ├─ Check riddle-1 namespace │ │
│  │  ├─ Run 6 verification checks  │ │
│  │  ├─ Detect state changes       │ │
│  │  └─ Queue report if changed    │ │
│  └────────────────────────────────┘ │
│                                      │
│  ┌────────────────────────────────┐ │
│  │  Reporter Worker (async)       │ │
│  │  ├─ Process report queue       │ │
│  │  ├─ HTTP POST to Supabase      │ │
│  │  └─ Retry on failure (3x)      │ │
│  └────────────────────────────────┘ │
│                                      │
│  ┌────────────────────────────────┐ │
│  │  Health Server :8080           │ │
│  │  ├─ GET /health (liveness)     │ │
│  │  ├─ GET /ready (readiness)     │ │
│  │  └─ GET /status (debug)        │ │
│  └────────────────────────────────┘ │
└─────────────────────────────────────┘
          │
          ├─ Read: Kubernetes API
          │  (pods, services, deployments, HPA, events)
          │
          └─ Write: Supabase API
             (POST /report-progress)
```

## Development

### Build Locally

```bash
go build -o progress-reconciler ./cmd/reconciler
```

### Run Tests

```bash
go test ./...
```

### Update Dependencies

```bash
go get k8s.io/client-go@latest
go mod tidy
```

## License

Part of the Bangalore Kubernetes Workshop.