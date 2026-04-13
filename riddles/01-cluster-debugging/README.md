# Riddle 1: Advanced Cluster Debugging

**Duration**: 45-60 minutes
**Difficulty**: Intermediate to Advanced

## Riddle Overview

A microservices e-commerce backend has been deployed to the `riddle-1` namespace. The system is broken — multiple services are failing and the application is not functional.

Your task: **investigate the cluster, find all the issues, and fix them.**

The issues vary in nature and difficulty. Some are straightforward, others require deeper investigation. Not everything that looks broken is the root cause, and not everything that looks healthy is actually working.

## Architecture

The application is a simplified e-commerce backend called **ShopFlow**:

```
                         ┌──────────────┐
             :30001  →   │  api-gateway │
                         └──────┬───────┘
                                │
        ┌───────────┬───────────┼───────────┬──────────────┐
        ▼           ▼           ▼           ▼              ▼
 ┌─────────────┐ ┌──────────┐ ┌──────────┐ ┌────────────┐ ┌───────────┐
 │order-service│ │inventory-│ │search-   │ │notification│ │analytics- │
 │             │ │service   │ │service   │ │-service    │ │service    │
 └──────┬──────┘ └──────────┘ └─────┬────┘ └────────────┘ └───────────┘
        │                           │
        ▼                           ▼
 ┌──────────────┐           ┌──────────────────┐
 │payment-      │           │recommendation-   │
 │processor     │           │service           │
 └──────────────┘           └──────────────────┘

   Infrastructure: cache-service, config-service, logging-service
```

| Service | Role |
|---------|------|
| **api-gateway** | Entry point. Hosts the ShopFlow admin dashboard. NodePort 30001. |
| **order-service** | Handles order creation and lifecycle. |
| **payment-processor** | Processes payments for completed orders. |
| **inventory-service** | Tracks product stock levels. Reads config from the cluster. |
| **search-service** | Product search and catalog validation. |
| **recommendation-service** | Personalized product recommendations. |
| **notification-service** | Sends order confirmations to customers. |
| **analytics-service** | Collects usage metrics and business analytics. |
| **cache/config/logging** | Infrastructure services supporting the backend. |

## Setup

```bash
cd riddles/01-cluster-debugging
./setup.sh
```

## Getting Started

After running setup, open the UI in your browser to start investigating:

```
http://localhost:30001
```

The dashboard shows live order processing status and will reflect your progress as you fix issues.

## Verification

```bash
./verify.sh
```

All 10 checks must pass to complete the riddle.

## Hints

If you get stuck, check the **"Riddle 1: Hints"** tab in the exercise sidebar for progressive hints.
