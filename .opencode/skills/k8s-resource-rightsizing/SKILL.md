---
name: k8s-resource-rightsizing
description: Diagnose OOMKilled pods and fix resource configuration by analyzing actual usage patterns
---

## What I do

I diagnose workloads that are crashing due to incorrect resource limits. I analyze the actual usage pattern of the application, determine the correct resource values, and apply a fix that keeps the workload stable.

## My methodology

### Step 1: Identify the symptom

```
kubectl get pods -n <namespace>
```

Look for:
- `OOMKilled` status — the kernel killed the container for exceeding its memory limit
- High restart counts — the pod keeps crashing and restarting
- Pods cycling between `Running` and `OOMKilled`

### Step 2: Confirm OOMKill

```
kubectl describe pod -l app=<name> -n <namespace>
```

Look in the container status for:
```
Last State:     Terminated
  Reason:       OOMKilled
  Exit Code:    137
```

Exit code 137 = SIGKILL from OOM killer. The container used more memory than its `limits.memory` allows.

### Step 3: Understand current resource configuration

```
kubectl get deployment <name> -n <namespace> -o yaml | grep -A 8 resources
```

Note:
- `requests.memory` — what the scheduler reserves (affects scheduling)
- `limits.memory` — the hard ceiling (exceeding this triggers OOMKill)
- The relationship: requests <= actual usage <= limits must hold for stability

### Step 4: Observe actual usage pattern

```
kubectl top pods -n <namespace>
```

Run this multiple times over 1-2 minutes. Many workloads have usage phases:
- **Startup phase**: low memory, application initializing
- **Ramp-up phase**: memory grows as workload increases
- **Steady state**: memory plateaus at operational level

The limit must accommodate the PEAK usage, not just the initial usage. If `kubectl top` shows 60Mi now but the pod OOMKills later, the workload ramps up over time.

Also check pod logs for clues about usage phases:
```
kubectl logs -l app=<name> -n <namespace>
```

### Step 5: Determine correct values

Calculate the right resource settings:

**Memory limit** = peak steady-state usage + 30% headroom
- If the workload peaks at 120Mi, set limit to ~160Mi
- This gives room for variance without waste

**Memory request** = typical steady-state usage
- Set this close to what the workload actually uses at steady state
- This affects scheduling — too low and the node gets overcommitted, too high and you waste capacity

**CPU request** = actual CPU usage (from `kubectl top`)
**CPU limit** = 2-4x the request to allow burst capacity

### Step 6: Apply the fix

```
kubectl patch deployment <name> -n <namespace> --type=json -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/memory", "value": "<new-request>"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value": "<new-limit>"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "<new-request>"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/cpu", "value": "<new-limit>"}
]'
```

Or use `kubectl edit deployment <name> -n <namespace>` to modify the values.

### Step 7: Verify stability

After applying the fix:

```
kubectl rollout status deployment/<name> -n <namespace>
kubectl get pods -n <namespace> -w
```

Watch for 2-3 minutes to confirm:
- No more OOMKills
- Restart count stays at 0 for the new pods
- All replicas reach and stay in Running+Ready state
- `kubectl top pods -n <namespace>` shows memory usage staying below the new limit

If pods still OOMKill, the limit is still too low — increase it further.

### What to report

After fixing, summarize:
- What the original resource config was (requests and limits)
- What the actual usage pattern looks like (phases, peak usage)
- Why the OOMKill happened (limit < peak usage)
- What the new values are and why
- Confirmation that pods are now stable

## When to use me

Use this skill when:
- Pods are being OOMKilled (exit code 137)
- Pods keep restarting with no obvious application errors
- You need to determine the correct memory/CPU values for a workload
- A workload runs fine initially but crashes after some time (phased usage pattern)

## Key principles

1. OOMKilled means the memory limit is too low for the actual workload — this is a configuration problem, not an application bug
2. Watch usage over time — many workloads have phases where memory grows after startup
3. Set limits based on peak usage + headroom, not on initial/average usage
4. Requests affect scheduling, limits affect stability — both matter
5. Always verify the fix by watching pods for several minutes to cover the full usage cycle
6. If metrics-server is not available, say so and fall back to log analysis and pod describe output
