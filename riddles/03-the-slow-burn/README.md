# Riddle 3: The Slow Burn

**Duration**: 30 minutes
**Difficulty**: Intermediate
**Goal**: Observe a workload that degrades over time, diagnose the pattern, and apply a correct fix with proper headroom

## Overview

A data processing workload (`stress-app`) is deployed and appears healthy at first. Pods show Running/Ready. But after about 60 seconds, they start OOMKilling and restarting. The cycle repeats: run fine for a minute, crash, restart.

This isn't a broken config that fails immediately — it's a **time-bomb**. The workload has usage phases: low memory initially, then ramps to a steady state that exceeds the configured limit. Your mission is to observe the pattern, understand why it happens, and apply a fix with proper headroom.

## The Problem

The `stress-app` deployment:
- **Memory request**: 64Mi (too low)
- **Memory limit**: 100Mi (too low for steady state)
- **2 replicas**, both affected

### Usage pattern
| Phase | Duration | Memory | Status |
|-------|----------|--------|--------|
| 1. Initial processing | ~60s | ~60Mi | Running fine |
| 2. Ramp up | ~30s | 60Mi → 120Mi | Climbing... |
| 3. Steady state | ongoing | ~120Mi | Exceeds 100Mi limit → **OOMKilled** |

The limit (100Mi) is fine for phase 1 but too low for the steady state. The kernel's OOM killer terminates the container (exit code 137) when it exceeds the limit.

## Setup

```bash
$HOME/workshop/riddles/03-the-slow-burn/setup.sh
```

## Diagnosis

### Step 1: Notice the restarts

```bash
kubectl get pods -n riddle-3 -w
```

Pods will show increasing restart counts. They cycle between Running and OOMKilled.

### Step 2: Confirm OOMKill

```bash
kubectl describe pod -l app=stress-app -n riddle-3
```

Look for:
```
Last State:     Terminated
  Reason:       OOMKilled
  Exit Code:    137
```

### Step 3: Observe memory over time

```bash
kubectl top pods -n riddle-3
```

Run this multiple times over 1-2 minutes. You'll see memory start at ~60Mi, then climb toward the limit.

### Step 4: Check current config

```bash
kubectl get deployment stress-app -n riddle-3 -o yaml | grep -A 8 resources
```

## The Fix

**Memory request** should be >= the steady-state usage (~120Mi).

**Memory limit** should be the steady-state usage + 30% headroom (~150-160Mi). Setting it to exactly 120Mi would leave zero margin for variance.

```bash
kubectl patch deployment stress-app -n riddle-3 --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/memory","value":"128Mi"},
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"160Mi"}
]'
```

Then watch for stability:
```bash
kubectl get pods -n riddle-3 -w
```

Wait 2-3 minutes to confirm no more OOMKills.

## Success Criteria

| Check | Points | Description |
|-------|--------|-------------|
| 1 | 300 | No OOMKilled pods + all pods running and ready |
| 2 | — | (included in check 1) |
| 3 | 100 | No recent OOMKill terminations |
| 4 | 200 | Memory request >= 120Mi |
| 5 | 400 | Memory limit >= 150Mi (proper headroom bonus) |

**Max score: 1000 points**

The 400-point bonus rewards setting the limit with proper headroom rather than just barely above 120Mi. In production, tight limits cause intermittent OOMKills from memory variance.

## Tips

1. **Don't rush the diagnosis** — the point is to observe the time-based pattern
2. **Run `kubectl top` multiple times** — once isn't enough to see the ramp
3. **Exit code 137 = SIGKILL** from the OOM killer
4. **Requests affect scheduling, limits affect stability** — both must be set correctly
5. **Watch for at least 2 minutes after fixing** — you need to see the workload survive past the phase-2 ramp
