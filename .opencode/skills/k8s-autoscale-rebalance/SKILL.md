---
name: k8s-autoscale-rebalance
description: Fix pending pods with CAST AI autoscaler, then optimize costs by rebalancing after temporary workloads complete
---

## What I do

I handle the full lifecycle of a capacity crunch followed by cost optimization: diagnose why pods are pending, use CAST AI to autoscale the cluster, wait for temporary workloads to finish, then rebalance to eliminate waste.

## Available tools

You have TWO MCP servers available:

1. **kubernetes** MCP — for running kubectl commands (get pods, describe, logs, etc.)
2. **castai** MCP — for CAST AI platform operations (autoscaler, rebalancing, cost analysis)

Use kubectl for diagnosis and verification. Use CAST AI MCP tools for autoscaler and rebalancing operations. List the available CAST AI tools first if you're unsure what's available.

## My methodology

### Phase 1: Diagnose the capacity problem

Use **kubernetes MCP** (kubectl) to assess the situation:

```
kubectl get pods -n <namespace>
kubectl get pods -n <namespace> --field-selector=status.phase=Pending
kubectl get events -n <namespace> --field-selector reason=FailedScheduling
```

Identify:
- How many pods are Pending and why (Insufficient cpu/memory)
- Total resource requests across all workloads
- Current node count and capacity: `kubectl get nodes -o wide` and `kubectl top nodes`
- Which workloads are temporary (Jobs) vs persistent (Deployments)

Calculate the gap: total requested resources minus total available capacity. This tells us how many additional nodes the autoscaler needs to provision.

### Phase 2: Enable autoscaling with CAST AI

Use **castai MCP tools** to manage the autoscaler. Typical workflow:

1. **List your clusters** — find the cluster ID for your current cluster
2. **Check autoscaler policies** — see if the autoscaler is enabled and what the current configuration is
3. **Enable the unschedulable pods policy** — this allows CAST AI to add nodes when pods can't be scheduled
4. **Monitor node provisioning** — use kubectl to watch nodes appear:
   ```
   kubectl get nodes -w
   kubectl get pods -n <namespace> -w
   ```
5. **Verify all pods are scheduled** — no more Pending pods, all Deployments have desired replicas ready

Important: The autoscaler adds nodes to match demand. It will provision enough capacity for ALL current workloads, including temporary Jobs.

### Phase 3: Wait for temporary workloads to complete

After autoscaling resolves the Pending pods, temporary batch Jobs will run to completion. Monitor with kubectl:

```
kubectl get jobs -n <namespace>
kubectl get pods -n <namespace>
```

Once Jobs show as Completed, the cluster now has significant waste — nodes that were needed for the Jobs are now nearly empty but still running and costing money.

Check the waste:
```
kubectl get nodes
kubectl top nodes
```

You should see several nodes with very low utilization now that the Jobs have finished. Only the persistent Deployments remain, and they need far fewer resources.

### Phase 4: Optimize costs with CAST AI rebalancing

Use **castai MCP tools** for rebalancing:

1. **Analyze optimization opportunities** — use CAST AI to check what savings are possible
2. **Check that PodDisruptionBudgets exist** — rebalancing respects PDBs to avoid downtime:
   ```
   kubectl get pdb -n <namespace>
   ```
3. **Trigger a rebalancing plan** — use CAST AI MCP to create and execute a rebalancing plan. CAST AI will:
   - Calculate the minimum nodes needed for the persistent workloads
   - Safely move pods off excess nodes (respecting PDBs)
   - Remove the empty nodes
4. **Monitor rebalancing progress** — use CAST AI MCP to check the plan status. This takes a few minutes.
5. **Verify the result** — fewer nodes, all workloads still healthy:
   ```
   kubectl get nodes
   kubectl get pods -n <namespace>
   kubectl top nodes
   ```

### What to report

After completing all phases, summarize:
- How many nodes were added by autoscaling (and why)
- How many nodes were removed by rebalancing
- Which workloads were temporary vs persistent
- The cost savings achieved (before: N nodes, after: M nodes)
- That all persistent workloads remained healthy throughout

## When to use me

Use this skill when:
- Pods are stuck in Pending due to insufficient cluster capacity
- The cluster has a mix of temporary (batch Jobs) and persistent (Deployments) workloads
- CAST AI is available and onboarded for the cluster
- You need to right-size the cluster after a capacity spike

## Key principles

1. Always diagnose before acting — understand what's Pending and why
2. Distinguish temporary workloads from persistent ones — this determines the "right" cluster size
3. Wait for Jobs to finish before rebalancing — rebalancing during peak load is wasteful
4. Verify PDBs before rebalancing — ensure zero-downtime migration
5. Show the cost impact in concrete terms — node count before vs after
