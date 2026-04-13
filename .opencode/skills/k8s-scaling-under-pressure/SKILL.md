---
name: k8s-scaling-under-pressure
description: Configure horizontal pod autoscaling, right-size resource requests, and add resilience for services under load
---

## What I do

I guide you through building scaling and resilience infrastructure for Kubernetes services under load: observe metrics, right-size resource requests, configure HPAs, add PodDisruptionBudgets, and spread replicas across nodes.

## Available tools

You have a **kubernetes** MCP server for running kubectl commands (get, describe, top, patch, autoscale, apply, etc.)

## My methodology

### Phase 1: Assess the situation

Check what's deployed and observe the load:

```
kubectl get pods -n riddle-2
kubectl top pods -n riddle-2
kubectl get hpa -n riddle-2
```

You should see:
- `web-frontend` and `order-service` with high CPU usage (single replica each)
- `load-generator` driving continuous traffic
- **No HPAs exist** — `kubectl get hpa` returns empty
- `notification-service` is stable with low CPU

Check the current resource requests:
```
kubectl get deployment web-frontend -n riddle-2 -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}'
```

The CPU request is `10m` — far below actual usage. This is the root cause: HPAs calculate utilization as `current_usage / request`. With a 10m request, even 200m usage looks like 2000% — HPA math will be broken.

### Phase 2: Right-size resource requests

Before creating HPAs, fix the CPU requests so HPA percentage targets make sense.

For `web-frontend`:
```
kubectl patch deployment web-frontend -n riddle-2 --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/cpu","value":"200m"}]'
```

For `order-service`:
```
kubectl patch deployment order-service -n riddle-2 --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/cpu","value":"200m"}]'
```

Wait for rollout:
```
kubectl rollout status deployment/web-frontend -n riddle-2
kubectl rollout status deployment/order-service -n riddle-2
```

### Phase 3: Create HPAs

Now create HPAs for both services:

```
kubectl autoscale deployment web-frontend -n riddle-2 --cpu-percent=50 --min=1 --max=5
kubectl autoscale deployment order-service -n riddle-2 --cpu-percent=50 --min=1 --max=5
```

Watch them react to the load:
```
kubectl get hpa -n riddle-2 -w
```

Within 30-60 seconds, HPA should scale both services to 2+ replicas. Verify:
```
kubectl get pods -n riddle-2
```

### Phase 4: Add PodDisruptionBudgets

Create PDBs so that scaling down or node maintenance doesn't kill all replicas at once:

```
kubectl apply -f - <<EOF
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
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: order-service-pdb
  namespace: riddle-2
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: order-service
EOF
```

Verify: `kubectl get pdb -n riddle-2`

### Phase 5: Spread replicas across nodes

After HPA scales web-frontend to multiple replicas, they may all land on one node. Add topology spread constraints:

```
kubectl patch deployment web-frontend -n riddle-2 --type=json -p='[{"op":"add","path":"/spec/template/spec/topologySpreadConstraints","value":[{"maxSkew":1,"topologyKey":"kubernetes.io/hostname","whenUnsatisfiable":"DoNotSchedule","labelSelector":{"matchLabels":{"app":"web-frontend"}}}]}]'
```

This triggers a rollout. Wait and verify pods are on different nodes:
```
kubectl get pods -l app=web-frontend -n riddle-2 -o wide
```

The NODE column should show at least 2 different node names.

### What to report

After completing all phases, summarize:
- Current HPA status for both services (target %, current %, replicas)
- PDB configuration (which services are protected)
- Topology spread result (which nodes have web-frontend pods)
- That all services are healthy and handling the load

## When to use me

Use this skill when:
- Services are running but CPU/memory is high with no autoscaling
- You need to configure HPAs for the first time
- Resource requests need tuning for HPA to work correctly
- Deployments need resilience (PDBs, topology spread)

## Key principles

1. **Fix requests before creating HPAs** — HPA math depends on correct resource requests
2. **Watch metrics with `kubectl top`** — understand actual usage before setting targets
3. **HPA needs 15-30 seconds** to react after metrics update
4. **PDBs protect availability** during scale-down and maintenance
5. **Topology spread prevents single-node failures** from taking out all replicas
