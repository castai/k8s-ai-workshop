---
name: k8s-cluster-debug
description: Systematically diagnose and fix a broken Kubernetes cluster with multiple interconnected failures
---

## What I do

I am an expert Kubernetes cluster debugger. When invoked, I follow a structured triage methodology to find and fix every issue in a broken cluster — not just the obvious ones.

## My methodology

### Step 1: Full cluster assessment

Get the big picture before diving into any single issue.

```
kubectl get pods -n <namespace> -o wide
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
kubectl get svc,endpoints -n <namespace>
kubectl describe resourcequota -n <namespace>
```

Categorize every pod into: Running+Ready, Running+NotReady, Pending, CrashLoopBackOff, ImagePullBackOff, CreateContainerConfigError, Init waiting, or no pods at all.

### Step 2: Investigate each failure category

Work through failures in dependency order — upstream fixes often resolve downstream issues automatically.

**No pods exist for a Deployment:**
- Check ReplicaSet events: `kubectl describe rs -l app=<name> -n <namespace>`
- Check ResourceQuota: `kubectl describe resourcequota -n <namespace>`
- A quota that's fully consumed prevents new pods from being created. The fix is to increase the quota or reduce requests on other workloads.

**Pods stuck in Pending:**
- `kubectl describe pod <name> -n <namespace>` — look at the Events section
- Check for nodeSelector/affinity mismatches, taint/toleration mismatches, and insufficient resources
- Pay close attention to toleration effects: `NoSchedule` vs `NoExecute` must match the node taint exactly
- Compare the pod's tolerations against `kubectl describe node <node> | grep -A5 Taint`

**Init containers stuck (Init:0/N):**
- `kubectl logs <pod> -c <init-container-name> -n <namespace>`
- Init containers often wait for dependent services. If the dependency is broken, fix that first — the init container resolves automatically. Do NOT modify the waiting pod.

**CrashLoopBackOff:**
- Check logs: `kubectl logs <pod> -n <namespace>` and `kubectl logs <pod> -n <namespace> --previous`
- If logs show clean startup with no errors, the app isn't crashing itself — something is killing it. Check liveness probe configuration very carefully.
- Compare liveness probe port and path against what the container actually serves. A one-digit port difference (8080 vs 8081) or wrong path (/ready vs /health) is a common subtle bug.
- If logs show "permission denied" or "cannot read configmap/secret", check RBAC: `kubectl auth can-i <verb> <resource> --as=system:serviceaccount:<ns>:<sa> -n <namespace>`
- For RBAC issues, check that RoleBinding subjects reference the correct ServiceAccount name (watch for typos like `inventory-service-sa` vs `inventory-sa`).

**CreateContainerConfigError:**
- The pod references a Secret or ConfigMap that is missing OR has the wrong key name
- Check `kubectl describe pod <name>` for the exact error
- Compare the key name in the pod spec (`secretKeyRef.key` or `configMapKeyRef.key`) against the actual keys in the Secret/ConfigMap. Key names are case-sensitive and hyphen vs underscore matters (`api-key` vs `API_KEY`).

**Running but not Ready (0/1):**
- The readiness probe is failing. Check the probe path: `kubectl get deploy <name> -o yaml | grep -A5 readinessProbe`
- Test what paths the app actually responds to: `kubectl exec <pod> -- wget -q -O- http://localhost:<port>/health`
- Common issue: probe checks `/ready` but app only serves `/health`

**Services with no endpoints:**
- Check if Service targetPort matches the container's listening port
- Check if Service selector labels match pod labels
- Traffic goes Service port -> targetPort -> container. If targetPort is wrong (e.g., 9090 when container listens on 8080), connections fail silently.

### Step 3: Watch for cascading failures

Some issues are effects, not causes. Before modifying a pod:
- Check if it depends on another service that's also broken
- Fix root causes first — downstream issues often self-resolve
- Example: if an init container waits for service X, and service X's pod is Pending due to a taint issue, fix the taint first

### Step 4: Watch for red herrings

Not everything that looks broken needs fixing:
- Suspended CronJobs may be intentional
- Unused ConfigMaps may be legacy
- Services with no endpoints might be for components not yet deployed (check annotations)

### Step 5: Verify after each fix

After every fix:
```
kubectl get pods -n <namespace>
kubectl get endpoints <service> -n <namespace>
```

Wait for pods to reach Running+Ready state before moving to the next issue. Some fixes take 30-60 seconds to propagate.

## When to use me

Use this skill when you encounter a Kubernetes namespace or cluster with multiple broken services. I am especially useful when:
- Multiple pods show different error states
- Issues appear interconnected
- Some pods look healthy but services are unreachable
- The root cause isn't obvious from the first error message

## Key principles

1. Assess before acting — get the full picture first
2. Fix in dependency order — upstream before downstream
3. Verify each fix before moving on
4. Explain what each error means and why the fix works
5. Distinguish root causes from cascading effects
6. Be suspicious of subtle differences: ports off by one digit, key names with different casing, similar but non-matching label values
