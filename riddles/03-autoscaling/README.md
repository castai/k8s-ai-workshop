# Riddle 3: Resource Right-Sizing

**Duration**: 30 minutes
**Difficulty**: Intermediate

## Riddle Overview

A data processing workload has been deployed with memory limits set too low. The pods run normally for about 1 minute (~60Mi usage), then ramp up to a steady state of ~120Mi when processing workloads — exceeding the 100Mi limit and getting OOMKilled. This cycle repeats every restart. Your task is to diagnose the issue and figure out the correct resource configuration.

## Problem Statement

The `stress-app` deployment keeps crashing. Pods start, run normally for ~1 minute, then get killed by the kernel's OOM killer when they reach steady-state processing. The current resource configuration:

- Memory request: 64Mi (too low)
- Memory limit: 100Mi (too low — workload needs ~120Mi for steady state)
- 2 replicas, both affected

**Your task: Diagnose the OOMKill issue and fix the resource configuration so the workload runs stably.**

## Setup

```bash
cd riddles/03-workload-autoscaling
./setup.sh
```

## Initial State

```bash
$ kubectl get pods -n riddle-3
NAME                          READY   STATUS      RESTARTS   AGE
stress-app-xxx                1/1     Running     2          3m
stress-app-yyy                0/1     OOMKilled   3          3m
```

Pods run for ~1 minute, then OOMKill, then restart — repeating continuously.

## Diagnosis Steps

### Step 1: Check Pod Status

```bash
kubectl get pods -n riddle-3
```

Look for `OOMKilled` status and high restart counts.

### Step 2: Inspect the OOMKill

```bash
# Describe a pod to see termination reason
kubectl describe pod -l app=stress-app -n riddle-3

# Look for:
#   Last State:     Terminated
#     Reason:       OOMKilled
#     Exit Code:    137
```

### Step 3: Check Events

```bash
kubectl get events -n riddle-3 --sort-by='.lastTimestamp'
```

### Step 4: Examine Current Resource Configuration

```bash
kubectl get deployment stress-app -n riddle-3 -o yaml | grep -A 8 resources
```

You'll see:
```yaml
resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 200m
    memory: 100Mi  # This is the problem!
```

### Step 5: Check Actual Resource Usage

```bash
kubectl top pods -n riddle-3
```

You'll see memory at ~60Mi during initial operation. After ~90 seconds, the workload ramps up to ~120Mi steady state and gets killed.

## Key Questions

1. What does `OOMKilled` mean and why does it happen?
2. What is the relationship between memory requests, limits, and actual usage?
3. How can you determine the right memory values for a workload?
4. How would you automate resource right-sizing so you don't have to guess?

## Success Criteria

- No OOMKilled pods
- All replicas running stably
- Resource requests and limits set appropriately for the workload

## Reset

```bash
./reset.sh
```

## Next Steps

Once complete, move to [Riddle 3: End-to-End Optimization](../05-riddle/)

---

**Estimated Time**: 30 minutes
