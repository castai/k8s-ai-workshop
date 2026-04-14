# Bonus: The Agent

**Duration:** Open-ended | **Difficulty:** Advanced

You solved the riddles with an AI assistant at your side. Now flip the script.

**Write an autonomous agent that solves all three riddles without human intervention.**

Your agent is a program you write from scratch -- any language, any approach. It calls an LLM for reasoning, uses kubectl to interact with the cluster, and uses the existing verify.sh scripts as its feedback signal. You start it, walk away, and come back to a fully healed cluster.

OpenCode is your IDE assistant for *writing* the agent. The agent itself runs on its own.

---

## The LLM API

The Kimchi API is OpenAI-compatible. Use any OpenAI SDK.

| Setting | Value |
|---------|-------|
| Base URL | `https://llm.kimchi.dev/openai/v1` |
| API Key | `$KIMCHI_API_KEY` (primary) or `$CASTAI_API_KEY` (fallback) |
| Model | Your choice -- pick from available models in your [Kimchi console](https://kimchi.dev) |

**Python:**

```python
import os
from openai import OpenAI

client = OpenAI(
    base_url="https://llm.kimchi.dev/openai/v1",
    api_key=os.environ.get("KIMCHI_API_KEY") or os.environ["CASTAI_API_KEY"],
)

response = client.chat.completions.create(
    model="<your-model>",
    messages=[{"role": "user", "content": "..."}],
)
```

**TypeScript:**

```typescript
import OpenAI from "openai";

const client = new OpenAI({
  baseURL: "https://llm.kimchi.dev/openai/v1",
  apiKey: process.env.KIMCHI_API_KEY || process.env.CASTAI_API_KEY,
});
```

**Quick connectivity test:**

```bash
# Pass your API key as an argument, or set KIMCHI_API_KEY / CASTAI_API_KEY
$HOME/workshop/riddles/04-the-agent/test-api.sh
```

---

## What Your Agent Must Do

For each riddle, your agent runs a loop:

1. **Reset** -- run the riddle's `setup.sh` to deploy the broken state
2. **Observe** -- use kubectl to inspect the cluster (pods, events, logs, describe, top)
3. **Reason** -- send observations to the LLM, ask it to diagnose and propose a fix
4. **Act** -- apply the fix using kubectl
5. **Verify** -- run the riddle's `verify.sh` and parse the JSON output
6. **Loop** -- if checks still fail, feed the failure details back to the LLM and repeat from step 2

Your agent solves all three riddles sequentially:

| Riddle | Setup | Verify | Namespace | Checks |
|--------|-------|--------|-----------|--------|
| 1 -- Cluster Debugging | `$HOME/workshop/riddles/01-cluster-debugging/setup.sh` | `$HOME/workshop/riddles/01-cluster-debugging/verify.sh` | `riddle-1` | 10 |
| 2 -- Scaling Under Pressure | `$HOME/workshop/riddles/02-scaling-under-pressure/setup.sh` | `$HOME/workshop/riddles/02-scaling-under-pressure/verify.sh` | `riddle-2` | 5 |
| 3 -- The Slow Burn | `$HOME/workshop/riddles/03-the-slow-burn/setup.sh` | `$HOME/workshop/riddles/03-the-slow-burn/verify.sh` | `riddle-3` | 5 |

---

## The Feedback Signal

Each `verify.sh` outputs JSON to stdout:

```json
{
  "checks_passed": 3,
  "total_checks": 10,
  "status": "in_progress",
  "checks": [
    {"name": "All deployments have desired replicas ready", "passed": true},
    {"name": "No pods in Pending state", "passed": false},
    {"name": "No pods in error states", "passed": false}
  ]
}
```

- **Exit code 0** -- all checks passed, riddle solved
- **Exit code 1** -- some checks still failing
- **`status`** -- one of `not_started`, `in_progress`, `completed`

The check names are human-readable. When "No pods in CrashLoopBackOff" fails, that is a clear starting point for the LLM to diagnose.

---

## Tools Your Agent Needs

Three capabilities:

1. **Run shell commands** -- subprocess calls to kubectl, setup.sh, verify.sh
2. **Call the LLM API** -- send observations, get back diagnosis and fix commands
3. **Parse JSON** -- read verify.sh output to decide whether to continue or move on

---

## Success Criteria

Your agent is successful when:

1. It runs `setup.sh` for each riddle to deploy the broken state
2. It autonomously diagnoses and fixes all issues
3. All `verify.sh` checks pass (exit code 0) for all three riddles
4. No human intervention at any point after starting the agent

**Bonus points** (bragging rights):

- Solving all three riddles in a single uninterrupted run
- Minimizing total wall-clock time
- Minimizing LLM API calls (efficient reasoning)
- Handling riddle 3's observation window gracefully

---

## What Makes a Good Agent

**Feed verify output back to the LLM.** The check names are descriptive. Include the full JSON in your next prompt so the LLM knows exactly what is still broken.

**Use kubectl for rich context.** Don't just check pod status. Use `kubectl describe`, `kubectl logs`, `kubectl get events`, and `kubectl top` to gather the information the LLM needs to reason about root causes.

**Handle cascading failures.** Riddle 1 has 8 issues across 11 services, and some failures cause others. Re-verify after each fix -- fixing one issue may resolve or reveal others.

**Be patient with Riddle 3.** The workload degrades over time. Running `kubectl top pods` once is not enough. Your agent should observe memory usage across multiple readings before diagnosing.

**Reset for re-testing.** Each `setup.sh` is idempotent -- it tears down the namespace and redeploys the broken state. Use this to test your agent from a clean slate every time.

**Think about your prompt.** The system prompt you give the LLM matters enormously. Consider telling it that it is a Kubernetes operations expert, which namespace to focus on, the output format you expect, and that it should reason step-by-step before proposing fixes.

**Start simple.** A bash script with curl calls works. You don't need a framework. Get the loop working first, then make it smarter.

---

## Riddle-Specific Notes

### Riddle 1: Cluster Debugging (hardest)

- 8 real issues, 10 verification checks, plus red herrings (not everything that looks broken needs fixing)
- Some issues only appear after fixing others -- init containers may be waiting on broken upstream services
- Resource quotas can block pod creation entirely
- Fix the dependency, not the waiter

### Riddle 2: Scaling Under Pressure

- Nothing is broken -- infrastructure is missing
- The agent needs to create HPAs, PDBs, and topology spread constraints
- Resource requests must be right-sized BEFORE creating HPAs (otherwise HPA math breaks)
- HPA metrics take 15-30 seconds to stabilize after creation

### Riddle 3: The Slow Burn

- Pods look healthy initially, then get OOMKilled after ~60-90 seconds
- The agent must observe memory usage over time (multiple `kubectl top` readings spaced apart)
- Setting the memory limit too high passes the basic checks but misses the 400-point headroom bonus
- Setting it too low means the fix does not actually fix the problem

---

## Getting Started

No setup script needed. This challenge reuses the existing riddle infrastructure.

1. Pick a language -- Python, TypeScript, Go, Bash, anything that can make HTTP calls and run subprocesses
2. Write your agent
3. Run it and watch it work (or debug why it doesn't)

Your API key is already configured from Step 0.
