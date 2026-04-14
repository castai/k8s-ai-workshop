# Riddle 3: The Slow Burn

**Duration:** 30 minutes | **Difficulty:** Intermediate

**Goal:** Observe a workload that degrades over time, diagnose the pattern, and apply a correct fix with proper headroom

## Overview

A data processing workload (`stress-app`) is deployed with 2 replicas. It appears healthy at first  - pods show Running/Ready. But something is wrong. **Watch it for a couple of minutes before touching anything.**

Your mission: observe, diagnose the pattern, understand *why* it's happening, and apply a fix.

## Setup

```bash
$HOME/workshop/riddles/03-the-slow-burn/setup.sh
```

## Your Mission

Start by asking opencode to help you investigate the cluster. The AI agent has been loaded with the k8s-resource-rightsizing skill to guide you through observing, diagnosing, and fixing the OOMKilled workload.

You can ask opencode things like:
- "Help me watch the pods to see what happens over time"
- "Show me how to check why the container was killed"
- "Guide me through observing the memory usage pattern over time"
- "Help me check the current resource configuration"
- "Show me how to apply a fix with proper headroom"
- "Help me verify the stability after applying the fix"

If you prefer to use kubectl directly:

1. **Watch the pods**  - `kubectl get pods -n riddle-3 -w` and give it time. What happens?
2. **Understand why**  - What killed the container? Check the pod description for termination details.
3. **Observe the usage pattern**  - Run `kubectl top pods -n riddle-3` several times over 1-2 minutes. How does memory usage change over time?
4. **Check the current resource configuration**  - What are the requests and limits set to? How do they compare to what you observed?
5. **Apply a fix**  - Set both the memory request and limit to values that will keep the workload stable. Don't just barely clear the bar  - think about what a production-safe margin looks like.
6. **Verify stability**  - Watch the pods for at least 2-3 minutes after your fix. One good minute isn't enough.

> **Key insight**: This isn't a broken config that fails immediately. The workload has *phases*. Don't assume the first minute of behavior tells the whole story.

## Scoring

This riddle uses a point system (max **1000 points**). You get points for stability, correct resource sizing, and proper headroom:

| Check | Points | What it measures |
|-------|--------|-----------------|
| 1-2 | 300 | Pods are stable  - no OOMKills, all running and ready |
| 3 | 100 | No recent OOMKill terminations |
| 4 | 200 | Memory request is right-sized to actual usage |
| 5 | 400 | Memory limit has proper production-safe headroom (bonus) |

The 400-point bonus rewards setting limits with real headroom. In production, tight limits cause intermittent failures from normal memory variance.

## Verification

```bash
$HOME/workshop/riddles/03-the-slow-burn/verify.sh
```

## Tips

- **Don't rush**  - the point of this riddle is to observe a time-based pattern
- **Run `kubectl top` multiple times**  - once isn't enough
- **Exit code 137** means something specific  - look it up if you don't know
- **Requests affect scheduling, limits affect stability**  - both matter
- **After fixing, watch for at least 2 minutes**  - you need to see the workload survive through its full cycle
