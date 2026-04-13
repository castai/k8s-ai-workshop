# Riddle 1: Advanced Debugging Hints

Progressive hints for each issue. Try to solve problems yourself before reading!

---

## Issue 1: analytics-service has no pods

### Level 1: Where to look
The Deployment exists (`kubectl get deploy -n riddle-1`) and shows 0/1 ready. But there are **no pods** for analytics-service. If there are no pods, what creates pods for a Deployment?

### Level 2: Narrowing down
Check the ReplicaSet:
```bash
kubectl get rs -n riddle-1
kubectl describe rs -l app=analytics-service -n riddle-1
```
Look at the **Events** section of the ReplicaSet. Also check:
```bash
kubectl get events -n riddle-1 | grep -i quota
```

### Level 3: The answer
A `ResourceQuota` is set on the namespace. The infrastructure services, api-gateway, and other backend services have consumed most of the CPU/memory quota. The analytics-service needs 100m CPU and 64Mi memory, but there isn't enough quota remaining.

```bash
kubectl describe resourcequota -n riddle-1
```

**Fix options**:
- Increase the ResourceQuota: `kubectl edit resourcequota namespace-quota -n riddle-1`
- Reduce analytics-service resource requests: `kubectl edit deploy analytics-service -n riddle-1`
- Reduce other services' resource requests to free up quota

> **Note**: After fixing the quota issue, analytics-service will hit a second error (`CreateContainerConfigError`). See Issue 8 for that fix.

---

## Issue 2: payment-processor is Pending

### Level 1: Where to look
```bash
kubectl describe pod -l app=payment-processor -n riddle-1
```
Look at the scheduling error message. It mentions both a node selector AND a taint.

### Level 2: Narrowing down
The pod has a `nodeSelector` for `workload-type: processing` and a matching node exists. The pod also has a `tolerations` section that looks correct at first glance. Compare very carefully:

```bash
# Check the node's taint
kubectl describe node | grep -A5 Taint

# Check the pod's toleration
kubectl get deploy payment-processor -n riddle-1 -o yaml | grep -A5 tolerations
```

### Level 3: The answer
The node has taint `processing=dedicated:NoSchedule` but the pod's toleration has effect `NoExecute` instead of `NoSchedule`. The effect must match exactly.

**Fix**:
```bash
kubectl edit deploy payment-processor -n riddle-1
# Change tolerations effect from "NoExecute" to "NoSchedule"
```

---

## Issue 3: order-service stuck in Init:0/2

### Level 1: Where to look
```bash
kubectl logs -n riddle-1 -l app=order-service -c wait-for-payment
```
The init container is waiting for something. What is it waiting for?

### Level 2: Narrowing down
The init container runs `wget` against `payment-processor-svc` and waits for it to return healthy. Is the `payment-processor-svc` service working? Does it have endpoints?

```bash
kubectl get endpoints payment-processor-svc -n riddle-1
```

### Level 3: The answer
This is a **cascading failure**. The init container waits for `payment-processor-svc` to return healthy, but payment-processor can't start (Issue 2). **Fix Issue 2 first**, and this issue resolves automatically.

You do NOT need to modify order-service at all.

---

## Issue 4: inventory-service stuck in Init:CrashLoopBackOff

### Level 1: Where to look
```bash
kubectl logs -l app=inventory-service -n riddle-1 -c load-config
```
The init container logs mention "Failed to read configmap inventory-config". Does the ConfigMap exist?

### Level 2: Narrowing down
```bash
kubectl get configmap inventory-config -n riddle-1
# It EXISTS! So why can't the app read it?
```

The pod isn't mounting the ConfigMap as a volume  - it's reading it via the **Kubernetes API**. What does an app need to call the K8s API?

```bash
kubectl auth can-i get configmaps --as=system:serviceaccount:riddle-1:inventory-sa -n riddle-1
```

### Level 3: The answer
The pod uses ServiceAccount `inventory-sa`. There's a Role and RoleBinding, but the RoleBinding references `inventory-service-sa` instead of `inventory-sa`.

```bash
kubectl get rolebinding -n riddle-1 -o yaml | grep -A3 subjects
```

**Fix**:
```bash
kubectl edit rolebinding inventory-configmap-binding -n riddle-1
# Change subjects[0].name from "inventory-service-sa" to "inventory-sa"
```

---

## Issue 5: notification-service is unreachable

### Level 1: Where to look
notification-service shows Running and Ready. The Service has endpoints. But can anything actually reach it through the Service?

```bash
# Try from another pod  - goes through the Service
kubectl exec -n riddle-1 <any-infrastructure-pod> -- wget -q -O- -T 3 http://notification-service:8080/health

# Compare with hitting the pod directly  - bypasses the Service
kubectl exec -n riddle-1 <any-infrastructure-pod> -- wget -q -O- -T 3 http://<pod-ip>:8080/health
```

### Level 2: Narrowing down
Traffic through the Service fails, but hitting the pod IP directly works. The problem is in how the Service routes traffic. Compare what the Service forwards to vs what the container actually listens on.

```bash
kubectl get svc notification-service -n riddle-1 -o yaml
kubectl get pods -l app=notification-service -n riddle-1 -o jsonpath='{.items[0].spec.containers[0].ports}'
```

### Level 3: The answer
The Service `targetPort` is `9090` but the container listens on port `8080`. Traffic arrives at the Service on port 8080 and gets forwarded to container port 9090, where nothing is listening.

**Fix**:
```bash
kubectl edit svc notification-service -n riddle-1
# Change targetPort from 9090 to 8080
```

---

## Issue 6: search-service keeps crashing (no errors in logs!)

### Level 1: Where to look
search-service is in CrashLoopBackOff. But check the logs:

```bash
kubectl logs -l app=search-service -n riddle-1
kubectl logs -l app=search-service -n riddle-1 --previous
```

The logs show completely normal startup. The app starts, loads data, and runs fine. No errors anywhere. Why is it being killed?

### Level 2: Narrowing down
If the logs are clean, the app isn't crashing itself  - something is killing it. Check the pod events:

```bash
kubectl describe pod -l app=search-service -n riddle-1
```

Look for "Liveness probe failed" in the events. Now look VERY carefully at the probe configuration  - compare every field between the readiness and liveness probes.

### Level 3: The answer
The liveness probe checks port **8081** but the container listens on port **8080**. The readiness probe correctly uses 8080. The one-digit difference is easy to miss.

**Fix**:
```bash
kubectl edit deploy search-service -n riddle-1
# Change livenessProbe.httpGet.port from 8081 to 8080
```

---

## Issue 7: recommendation-service is Running but not Ready

### Level 1: Where to look
The pod shows Running but `0/1` Ready. The service has no endpoints. Check the pod events:

```bash
kubectl describe pod -l app=recommendation-service -n riddle-1
```

Look for probe failure messages.

### Level 2: Narrowing down
The events show a readiness probe failing. What path is the probe checking? What path does the app actually serve?

```bash
kubectl get deploy recommendation-service -n riddle-1 -o yaml | grep -A5 readinessProbe
```

Then test: what does the app actually respond to?

```bash
kubectl exec -n riddle-1 <recommendation-pod> -- wget -q -O- http://localhost:8080/ready
kubectl exec -n riddle-1 <recommendation-pod> -- wget -q -O- http://localhost:8080/health
```

### Level 3: The answer
The readiness probe checks `/ready` but the app only serves `/health`. The `/ready` path returns 404, so the probe always fails and the pod is never marked Ready.

**Fix**:
```bash
kubectl edit deploy recommendation-service -n riddle-1
# Change readinessProbe.httpGet.path from "/ready" to "/health"
```

---

## Issue 8: analytics-service won't start (secret key error)

> **Prerequisite**: You must fix Issue 1 (quota) first before this error becomes visible. Once the pod can be created, it will show `CreateContainerConfigError`.

### Level 1: Where to look
```bash
kubectl get pods -l app=analytics-service -n riddle-1
kubectl describe pod -l app=analytics-service -n riddle-1
```

The error is `CreateContainerConfigError`. This usually means a missing Secret or ConfigMap.

### Level 2: Narrowing down
The pod references a Secret. Does it exist?

```bash
kubectl get secret -n riddle-1
kubectl get secret analytics-credentials -n riddle-1 -o yaml
```

The Secret exists! So what's wrong? Look closely at the key names in the Secret vs what the pod expects.

### Level 3: The answer
The Secret has key `api-key` but the pod's `secretKeyRef` expects key `API_KEY`. Kubernetes key names are case-sensitive and hyphen vs underscore matters.

**Fix**:
```bash
kubectl edit deploy analytics-service -n riddle-1
# Change secretKeyRef.key from "API_KEY" to "api-key"
```

---

## Debugging Cheat Sheet

| Symptom | What to Check |
|---------|--------------|
| No pods for a Deployment | `kubectl describe rs`, `kubectl get events`, ResourceQuotas |
| Pod Pending | `kubectl describe pod` → scheduling errors, node taints, nodeSelector, tolerations |
| Init:0/N | `kubectl logs -c <init-container>`, check what the init container depends on |
| CrashLoopBackOff / Init:CrashLoopBackOff (with errors) | `kubectl logs -c <container>`, check RBAC, Secrets, ServiceAccounts |
| CrashLoopBackOff (no errors) | `kubectl describe pod` → check liveness probe config carefully (port, path) |
| CreateContainerConfigError | Check referenced Secrets/ConfigMaps  - key names are case-sensitive |
| Running but unreachable | Service port/targetPort, Service selectors, NetworkPolicies |

---

## Red Herrings

Not everything that looks suspicious is broken:
- The `db-backup` CronJob is intentionally suspended  - it's fine
- The `legacy-config` ConfigMap is old but not referenced by anything active
- The `monitoring-svc` Service has no endpoints because its deployment hasn't been created yet

---

## Still Stuck?

1. Run `./verify.sh` to see exactly which checks are failing
2. Think about **dependencies between issues**  - some fixes unlock others
3. Ask the instructor for help
