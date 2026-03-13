# Riddle 2: Autoscaler & Rebalancing

**Duration**: 30-45 minutes
**Difficulty**: Intermediate
**Goal**: Enable CAST AI autoscaler to fix pending pods, then rebalance the cluster after batch jobs complete

## Overview

Your cluster is running a small e-commerce platform alongside heavy batch jobs (data migration, index rebuild, cache warmup). The combined workloads exceed the cluster's capacity - several pods are stuck in `Pending` state.

Here's the twist: the batch jobs only run for about 60 seconds. Once they complete, the cluster will have far more nodes than needed for the remaining microservices, creating significant waste.

Your mission:

1. **Fix pending pods** - Enable the CAST AI autoscaler so new nodes are added and all pods can run
2. **Wait for batch jobs to complete** - After ~60 seconds the jobs finish, leaving excess nodes
3. **Optimize costs** - Trigger CAST AI rebalancing to consolidate onto fewer nodes

## The Problem

The cluster currently has **2 worker nodes**, but the deployed workloads request more resources than 2 nodes can provide.

### Persistent Workloads (stay running)

| Workload | Replicas | CPU request | Memory request |
|----------|----------|------------|----------------|
| web-frontend | 2 | 200m | 256Mi |
| order-service | 2 | 200m | 256Mi |
| notification-service | 1 | 100m | 128Mi |

**Persistent total**: ~1 CPU / ~1.2Gi - fits on 2 nodes easily.

### Temporary Batch Jobs (complete after ~60s)

| Job | Pods | CPU request | Memory request |
|-----|------|------------|----------------|
| data-migration | 3 | 3 CPU | 3Gi |
| index-rebuild | 3 | 3 CPU | 3Gi |
| cache-warmup | 2 | 2.5 CPU | 2Gi |

**Temporary total**: ~23 CPU / ~22Gi - forces autoscaler to add 4+ extra nodes.

**Combined total**: ~24 CPU - way more than 2 nodes can handle.

### Why Rebalancing Saves Money

After the autoscaler adds nodes and the batch jobs complete (~60s), the cluster will have 5-6 nodes but only need 2 for the remaining microservices. That's 3-4 nodes sitting nearly empty, wasting money. Rebalancing consolidates the persistent workloads onto fewer nodes and removes the excess.

## Setup

```bash
cd riddles/02-autoscaler-rebalancing
./setup.sh
```

This deploys:
- Namespace `riddle-2` with 3 microservices + 3 batch jobs (13 total pods)
- PodDisruptionBudgets for safe rebalancing
- Total resource requests exceeding 2-node capacity -> pending pods

## Step 1: Fix Pending Pods

### Observe the Problem

```bash
kubectl get pods -n riddle-2
# Several pods will show "Pending"

kubectl get events -n riddle-2 --field-selector reason=FailedScheduling
# Shows "Insufficient cpu" / "Insufficient memory"
```

### Use CAST AI MCP to Enable Autoscaler

Talk to Claude with CAST AI MCP tools:

```
"Enable the autoscaler for my cluster so that pending pods in riddle-2 can be scheduled"

"What nodes would CAST AI add to handle the pending pods?"

"Check if all pods in riddle-2 are now running"
```

### Verify Step 1

```bash
./verify.sh
# All 4 Step 1 checks should pass (no pending pods, all deployments ready)
```

## Step 2: Wait for Batch Jobs to Complete

After the autoscaler adds nodes, wait about 60 seconds for the batch jobs to finish:

```bash
# Watch jobs complete
kubectl get jobs -n riddle-2 -w

# After jobs complete, check node utilization - lots of waste!
kubectl get nodes
kubectl top nodes
```

## Step 3: Optimize Costs with Rebalancing

Now the cluster has excess nodes running nearly empty. Use CAST AI to fix this:

```
"Analyze the cluster for cost optimization opportunities"

"What savings can rebalancing achieve for my cluster?"

"Trigger a rebalancing plan - I want to minimize costs while keeping all workloads running"

"Show me the rebalancing progress"
```

CAST AI rebalancing will:
- Consolidate persistent workloads onto fewer nodes
- Remove the excess empty nodes left after batch jobs completed
- Right-size the remaining nodes for the actual workload

## Success Criteria

| Check | Description |
|-------|-------------|
| 1 | All deployments have desired replicas ready |
| 2 | No pods in Pending state |
| 3 | No pods in error states |
| 4 | All deployment pods fully Ready |
| 5 | CAST AI rebalancing completed successfully |

## Tips

1. **Start with `kubectl get pods -n riddle-2`** to see the pending pods
2. **Use CAST AI MCP** to enable autoscaler - don't try to manually add nodes
3. **Wait for jobs to complete** before triggering rebalancing - that's when the waste appears
4. **Rebalancing takes a few minutes** - CAST AI needs to move workloads and remove old nodes
5. **PDBs are already configured** - rebalancing can safely evict pods without downtime

## Reset

```bash
./reset.sh
```

## Next Steps

After completing this riddle:
- Review the cost savings in the CAST AI console
- Compare node count before and after rebalancing
