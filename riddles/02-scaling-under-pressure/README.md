# Riddle 2: Scaling Under Pressure

**Duration:** 30-45 minutes | **Difficulty:** Intermediate

**Goal:** Configure horizontal pod autoscaling and resilience for services under load

## Overview

An e-commerce platform is deployed with three services: `web-frontend`, `order-service`, and `notification-service`. Everything runs fine at low traffic. Then a load generator starts driving continuous requests to the frontend and order service.

The services are struggling  - CPU usage is high, response times are degrading. But there's nothing broken. The problem is that nobody configured autoscaling, resource requests are unrealistically low, there are no PodDisruptionBudgets, and replicas aren't spread across nodes.

Your mission: **build the scaling and resilience infrastructure** that should have been there from the start.

## What's Deployed

| Service | Replicas | CPU Request | Role |
|---------|----------|------------|------|
| web-frontend | 1 | 10m | Serves HTTP traffic |
| order-service | 1 | 10m | Processes orders |
| notification-service | 1 | 50m | Lightweight notification sender |
| load-generator | 1 |  - | Drives continuous traffic to frontend and orders |

## Setup

```bash
$HOME/workshop/riddles/02-scaling-under-pressure/setup.sh
```

## Your Mission

Start by asking opencode to help you investigate the cluster. The AI agent has been loaded with the k8s-scaling-under-pressure skill to guide you through configuring scaling and resilience.

You can ask opencode things like:
- "Help me observe what's happening with the services under load"
- "Show me how to right-size resource requests for autoscaling"
- "Guide me through adding horizontal pod autoscaling"
- "Help me protect availability with PodDisruptionBudgets"
- "Show me how to spread replicas across nodes"

If you prefer to use kubectl directly, the load generator is already running. Services are struggling. Your job is to build the scaling and resilience infrastructure that's missing. There are **5 things** you need to do:

1. **Observe**  - Start by understanding what's happening. How much CPU are the services actually using? (`kubectl top pods -n riddle-2`)
2. **Right-size resource requests**  - The CPU requests don't match reality. Why does this matter for autoscaling? (Hint: HPA calculates utilization as `current_usage / request`)
3. **Add horizontal pod autoscaling**  - Services need to scale with demand
4. **Protect availability**  - What happens if all replicas get evicted at once during a scale-down?
5. **Spread replicas across nodes**  - After scaling up, are replicas actually distributed? What if a node goes down?

> **Important**: The order matters. Think about why step 2 must come before step 3.

> **Note**: `notification-service` is lightweight and doesn't need autoscaling.

## Success Criteria

| Check | Description |
|-------|-------------|
| 1 | HPA exists for web-frontend and has scaled to >= 2 replicas |
| 2 | HPA exists for order-service and has scaled to >= 2 replicas |
| 3 | All deployments have desired replicas ready |
| 4 | PodDisruptionBudgets exist (at least 2) |
| 5 | web-frontend replicas spread across multiple nodes |

## Verification

```bash
$HOME/workshop/riddles/02-scaling-under-pressure/verify.sh
```

All 5 checks must pass to complete the riddle.

## Tips

- **Start with `kubectl top pods -n riddle-2`**  - see the CPU pressure before changing anything
- **Watch HPA with `-w`**  - it takes 15-30 seconds for metrics to update after creation
- **Topology spread requires >= 2 replicas**  - wait for HPA to scale before verifying
