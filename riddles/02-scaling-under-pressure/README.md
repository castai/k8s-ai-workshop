# Riddle 2: Scaling Under Pressure

**Duration**: 30-45 minutes
**Difficulty**: Intermediate
**Goal**: Configure horizontal pod autoscaling and resilience for services under load

## Overview

An e-commerce platform is deployed with three services: `web-frontend`, `order-service`, and `notification-service`. Everything runs fine at low traffic. Then a load generator starts driving continuous requests to the frontend and order service.

The services are struggling — CPU usage is high, response times are degrading. But there's nothing broken. The problem is that nobody configured autoscaling, resource requests are unrealistically low, there are no PodDisruptionBudgets, and replicas aren't spread across nodes.

Your mission: **build the scaling and resilience infrastructure** that should have been there from the start.

## The Problem

### What's deployed
| Service | Replicas | CPU Request | Image |
|---------|----------|------------|-------|
| web-frontend | 1 | 10m | registry.k8s.io/hpa-example |
| order-service | 1 | 10m | registry.k8s.io/hpa-example |
| notification-service | 1 | 50m | nginx:1.27-alpine |
| load-generator | 1 | — | busybox (wget loop) |

### What's missing
1. **No HPAs** — services can't scale with demand
2. **CPU requests are wrong** — 10m is far below actual usage (~200-400m under load), making HPA percentage math useless
3. **No PodDisruptionBudgets** — scaling down could kill all replicas simultaneously
4. **No topology spread** — after HPA scales up, all replicas land on one node

## Setup

```bash
$HOME/workshop/riddles/02-scaling-under-pressure/setup.sh
```

## Step 1: Observe the Load

```bash
kubectl top pods -n riddle-2
# web-frontend and order-service will show high CPU

kubectl get hpa -n riddle-2
# No HPAs exist
```

## Step 2: Right-Size Resource Requests

The CPU request on web-frontend and order-service is `10m`. Under load, actual usage is `200-400m`. HPA calculates utilization as `current / request` — with a 10m request and 300m usage, that's 3000% utilization. The HPA would try to create dozens of replicas.

Set CPU requests to a realistic value (e.g., `200m`) so HPA targets work correctly.

## Step 3: Create HPAs

```bash
kubectl autoscale deployment web-frontend -n riddle-2 --cpu-percent=50 --min=1 --max=5
kubectl autoscale deployment order-service -n riddle-2 --cpu-percent=50 --min=1 --max=5
```

Watch the HPAs scale:
```bash
kubectl get hpa -n riddle-2 -w
```

## Step 4: Add PodDisruptionBudgets

Create PDBs so that scaling down (or node maintenance) doesn't kill all replicas at once:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: web-frontend-pdb
  namespace: riddle-2
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: web-frontend
```

## Step 5: Spread Replicas Across Nodes

After HPA scales up web-frontend, all replicas may land on one node. Add topology spread constraints to distribute them:

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels:
        app: web-frontend
```

## Success Criteria

| Check | Description |
|-------|-------------|
| 1 | HPA exists for web-frontend and has scaled to >= 2 replicas |
| 2 | HPA exists for order-service and has scaled to >= 2 replicas |
| 3 | All deployments have desired replicas ready |
| 4 | PodDisruptionBudgets exist (at least 2) |
| 5 | web-frontend replicas spread across multiple nodes |

## Tips

1. **Start with `kubectl top pods -n riddle-2`** — see the CPU pressure
2. **Fix resource requests first** — HPA can't work properly with 10m requests
3. **Watch HPA with `-w`** — it takes 15-30 seconds for metrics to update
4. **Don't scale notification-service** — it's lightweight and doesn't need HPA
5. **Topology spread requires >= 2 replicas** — wait for HPA to scale before checking
