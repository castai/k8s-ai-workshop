# Kubernetes AI-Powered Operations Workshop

A hands-on workshop where participants use AI agents (OpenCode + Claude/Qwen via MCP) to diagnose and fix progressively complex Kubernetes cluster issues across three interactive riddle scenarios.

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
|   |-- k8s-autoscale-rebalance/    #   Riddle 2: autoscaler + cost optimization
|   +-- k8s-resource-rightsizing/   #   Riddle 3: OOMKill diagnosis + resource tuning
|
|-- riddles/                        # The three workshop challenges
|   |-- 01-cluster-debugging/       #   Riddle 1: fix 11 broken microservices
|   |   |-- setup.sh                #     Deploy broken scenario
|   |   |-- verify.sh               #     Check progress (10 checks)
|   |   +-- broken/                 #     Intentionally broken K8s manifests
|   |
|   |-- 02-autoscaler-rebalancing/  #   Riddle 2: autoscale then rebalance
|   |   |-- setup.sh                #     Deploy overprovisioned workloads
|   |   |-- verify.sh               #     Check progress (5 checks)
|   |   +-- broken/                 #     Workload + batch job manifests
|   |
|   |-- 03-autoscaling/             #   Riddle 3: fix OOMKilled workload
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
|-- PARTICIPANT_GUIDE.md            # Workshop companion (setup steps, riddle instructions)
+-- AGENTS.md                       # Dynamic file rewritten by each riddle's setup.sh
```

## Quick Start

### Instructor Setup

```bash
# 1. Create the kind cluster (4 nodes)
./setup/install-kind.sh

# 2. Install monitoring stack (optional, auto-installed by riddle 3)
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

# 3. Before Riddle 2: configure CAST AI
./riddles/common/setup-opencode.sh --with-castai

# 4. Start Riddle 2
cd riddles/02-autoscaler-rebalancing
./setup.sh
./verify.sh         # 5 checks, pass/fail

# 5. Start Riddle 3
cd riddles/03-autoscaling
./setup.sh
./verify.sh         # 5 checks, pass/fail + score out of 1000
```

## The Three Riddles

### Riddle 1: Advanced Cluster Debugging (45-60 min)

Deploy a broken 11-service e-commerce backend ("ShopFlow") and systematically fix all interconnected issues: resource quota exhaustion, missing tolerations, ConfigMap key mismatches, selector mismatches, probe misconfigurations, init container dependency chains, and red herrings.

- **Namespace**: `riddle-1`
- **Entry point**: `http://localhost:8080` (port-forwarded api-gateway dashboard)
- **Checks**: 10 (deployments, pods, init containers, services, HTTP connectivity)
- **Skill**: `k8s-cluster-debug` — 5-step structured debugging methodology

### Riddle 2: Autoscaler & Rebalancing (30-45 min)

Three heavy batch jobs (data-migration, index-rebuild, cache-warmup) requesting ~24 CPU cause pending pods. Use CAST AI to autoscale the cluster, wait for jobs to complete (~60s), then rebalance to remove the now-empty nodes.

- **Namespace**: `riddle-2`
- **Prerequisite**: CAST AI API key + cluster onboarded to CAST AI console
- **Checks**: 5 (pod health + CAST AI rebalancing API status)
- **Skill**: `k8s-autoscale-rebalance` — 4-phase capacity and cost optimization

### Riddle 3: Resource Right-Sizing (30 min)

A stress-app has memory limit=100Mi but its usage ramps to ~120Mi after 60 seconds, causing repeated OOMKills. Diagnose the pattern, set correct resource requests/limits, and optionally apply CAST AI WOOP recommendations.

- **Namespace**: `riddle-3`
- **Checks**: 5 + scoring system (max 1000 pts, 400 bonus for WOOP)
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
| [PARTICIPANT_GUIDE.md](PARTICIPANT_GUIDE.md) | Participants | Step-by-step workshop companion |
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
