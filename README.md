# Kubernetes AI-Powered Operations Workshop

A hands-on workshop where participants use AI agents (OpenCode + Nemotron via MCP) to diagnose and fix progressively complex Kubernetes cluster issues across three interactive riddle scenarios.

## Repository Structure

```
k8s-ai-workshop/
|
|-- setup/                          # Cluster and tooling bootstrap
|   |-- kind-cluster-config.yaml    #   Kind cluster definition (1 CP + 3 workers, K8s 1.31)
|   |-- install-kind.sh             #   Create kind cluster with prereq checks
|   |-- install-monitoring.sh       #   Deploy Prometheus + Grafana + metrics-server
|   +-- verify-setup.sh             #   Validate cluster health (10-category check)
|
|-- monitoring/                     # Helm values for observability stack
|   |-- prometheus/values.yaml      #   kube-prometheus-stack (NodePort 30090/30091)
|   |-- metrics-server/values.yaml  #   metrics-server for kubectl top / HPA
|   +-- grafana/dashboards/         #   Dashboard docs and PromQL examples
|
|-- .opencode/skills/               # AI agent skill definitions (structured methodologies)
|   |-- k8s-cluster-debug/          #   Riddle 1: systematic multi-failure diagnosis
|   |-- k8s-scaling-under-pressure/ #   Riddle 2: HPA, resource requests, PDBs, topology spread
|   +-- k8s-resource-rightsizing/   #   Riddle 3: OOMKill diagnosis + resource tuning
|
|-- riddles/                        # The three workshop challenges
|   |-- 01-cluster-debugging/       #   Riddle 1: fix 11 broken microservices
|   |   |-- setup.sh                #     Deploy broken scenario
|   |   |-- verify.sh               #     Check progress (10 checks)
|   |   +-- broken/                 #     Intentionally broken K8s manifests
|   |
|   |-- 02-scaling-under-pressure/  #   Riddle 2: configure scaling under load
|   |   |-- setup.sh                #     Deploy services + load generator
|   |   |-- verify.sh               #     Check progress (5 checks)
|   |   +-- broken/                 #     Workload + load generator manifests
|   |
|   |-- 03-the-slow-burn/             #   Riddle 3: observe and fix OOMKilled workload
|   |   |-- setup.sh                #     Deploy stress-app with bad limits
|   |   |-- verify.sh               #     Check progress + scoring (5 checks)
|   |   +-- broken/                 #     stress-app manifest
|   |
|   +-- common/                     # Shared utilities
|       |-- lib.sh                  #   Colors, step runner, state file, verifier helpers
|       |-- bootstrap.sh            #   Kimchi CLI + OpenCode one-shot setup
|       |-- setup-opencode.sh       #   Configure MCP servers + install skills
|       |-- install-opencode.sh     #   OpenCode binary installation
|       +-- troubleshooting.md      #   Comprehensive troubleshooting guide
|
|-- progress-reconciler/            # Background progress tracking service (Go)
|   |-- cmd/reconciler/main.go      #   Entry point (reconciler loop + verify CLI)
|   |-- internal/
|   |   |-- verifiers/              #   Verification logic for all 3 riddles
|   |   |-- reconciler/             #   Reconciliation loop + state management
|   |   |-- reporter/               #   Supabase HTTP reporting + rate limiting
|   |   +-- config/                 #   Configuration loading (ConfigMap or defaults)
|   |-- pkg/health/                 #   Health/readiness/status HTTP endpoints
|   |-- manifests/                  #   K8s deployment manifests (RBAC, ConfigMap, Deployment)
|   |-- deploy.sh                   #   One-command deployment script
|   +-- Dockerfile                  #   Multi-stage Go build
|
|-- scripts/                        # Utility scripts
|   |-- cleanup-all.sh              #   Full teardown (kind + Docker prune)
|   +-- health-check-kind.sh        #   Cluster health check (10 categories)
|
|-- tests/
|   +-- test-riddle-scripts.sh      #   E2E tests: setup idempotency, verify scripts, PID leaks
|
|-- .github/workflows/
|   |-- test-scripts.yml            #   CI: spin up kind, run all riddle tests
|   +-- progress-reconciler.yml     #   CI: build reconciler Docker image
|
+-- AGENTS.md                       # Dynamic file rewritten by each riddle's setup.sh
```

## Quick Start

### Instructor Setup

```bash
# 1. Create the kind cluster (4 nodes)
./setup/install-kind.sh

# 2. Install monitoring stack (optional, auto-installed by riddles 2 and 3)
./setup/install-monitoring.sh

# 3. Verify everything is healthy
./setup/verify-setup.sh
```

### Participant Flow

```bash
# 1. Configure AI tooling
./riddles/common/setup-opencode.sh

# 2. Start Riddle 1
cd riddles/01-cluster-debugging
./setup.sh          # deploys broken scenario
opencode            # AI agent loads skill from AGENTS.md
./verify.sh         # 10 checks, pass/fail

# 3. Start Riddle 2
cd riddles/02-scaling-under-pressure
./setup.sh
./verify.sh         # 5 checks, pass/fail

# 4. Start Riddle 3
cd riddles/03-the-slow-burn
./setup.sh
./verify.sh         # 5 checks, pass/fail + score out of 1000
```

## The Three Riddles

Each riddle teaches a distinct operational pattern:

### Riddle 1: Advanced Cluster Debugging (45-60 min) — *Fix what's broken*

Deploy a broken 11-service e-commerce backend ("ShopFlow") and systematically fix all interconnected issues: resource quota exhaustion, missing tolerations, ConfigMap key mismatches, selector mismatches, probe misconfigurations, init container dependency chains, and red herrings.

- **Namespace**: `riddle-1`
- **Entry point**: `http://localhost:8080` (port-forwarded api-gateway dashboard)
- **Checks**: 10 (deployments, pods, init containers, services, HTTP connectivity)
- **Skill**: `k8s-cluster-debug` — 5-step structured debugging methodology

### Riddle 2: Scaling Under Pressure (30-45 min) — *Build what's missing*

An e-commerce platform is running fine at low traffic. A load generator starts driving requests, and services struggle — but nothing is broken. The problem is that nobody configured autoscaling. Configure HPAs, right-size resource requests, add PodDisruptionBudgets, and spread replicas across nodes.

- **Namespace**: `riddle-2`
- **Checks**: 5 (HPAs active, deployments ready, PDBs exist, topology spread)
- **Skill**: `k8s-scaling-under-pressure` — 5-phase scaling and resilience methodology

### Riddle 3: The Slow Burn (30 min) — *Observe and respond*

A data processing workload appears healthy at first, but after ~60 seconds pods start OOMKilling. The memory limit is too low for the workload's steady-state usage. Observe the degradation pattern over time, diagnose why it happens, and apply a fix with proper headroom.

- **Namespace**: `riddle-3`
- **Checks**: 5 + scoring system (max 1000 pts, 400 bonus for proper headroom)
- **Skill**: `k8s-resource-rightsizing` — 7-step OOMKill diagnosis methodology

## Progress Tracking

The `progress-reconciler` is a Go service deployed in-cluster that continuously monitors all three riddle namespaces and reports progress to a Supabase dashboard.

- **Deployed automatically** by the first riddle's `setup.sh`
- **Reconciliation interval**: every 5 seconds
- **Reports**: check pass/fail counts per riddle to Supabase on state changes
- **Status endpoint**: `http://localhost:8080/status` (JSON) via the health server
- **CLI mode**: the same binary doubles as the verification engine for `verify.sh` scripts

```bash
# Check reconciler status
kubectl get pods -n progress-reconciler
kubectl port-forward -n progress-reconciler svc/progress-reconciler 8080:8080
curl localhost:8080/status
```

The verify.sh scripts call `reconciler verify --riddle N --format json` to run checks, eliminating duplication between the CLI and the background service.

## Key Documentation

| Document | Audience | Content |
|----------|----------|---------|
| [riddles/common/troubleshooting.md](riddles/common/troubleshooting.md) | Everyone | Common issues and fixes |
| [progress-reconciler/README.md](progress-reconciler/README.md) | Developers | Reconciler architecture and deployment |
| Each riddle's `README.md` | Participants | Challenge description, architecture, success criteria |
| Each skill's `SKILL.md` | AI agent | Structured methodology loaded via AGENTS.md |

## Cleanup

```bash
# Remove all riddle namespaces and resources
./scripts/cleanup-all.sh

# Or just delete the cluster
kind delete cluster --name workshop-cluster
```
