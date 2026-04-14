# Riddle 1: Advanced Debugging Hints

Progressive hints for each issue. Try to solve problems yourself before reading!

---

## Issue 1: analytics-service has no pods

### Level 1: Where to look
The Deployment exists and shows 0/1 ready. But there are **no pods** for analytics-service. If there are no pods, what creates pods for a Deployment?

### Level 2: Narrowing down
Check the ReplicaSet events and ResourceQuota. You can use opencode to help investigate:
- Ask opencode to describe the ReplicaSet for analytics-service
- Ask opencode to check events for quota issues
- Ask opencode to describe the ResourceQuota

### Level 3: The answer
A `ResourceQuota` is set on the namespace. The infrastructure services, api-gateway, and other backend services have consumed most of the CPU/memory quota. The analytics-service needs 100m CPU and 64Mi memory, but there isn't enough quota remaining.

**Fix options** (you can ask opencode to help with these):
- Increase the ResourceQuota
- Reduce analytics-service resource requests  
- Reduce other services' resource requests to free up quota

> **Note**: After fixing the quota issue, analytics-service will hit a second error (`CreateContainerConfigError`). See Issue 8 for that fix.

---

## Issue 2: payment-processor is Pending

### Level 1: Where to look
Look at the scheduling error message for payment-processor pods. It mentions both a node selector AND a taint.

### Level 2: Narrowing down
The pod has a `nodeSelector` for `workload-type: processing` and a matching node exists. The pod also has a `tolerations` section that looks correct at first glance. Compare very carefully:
- Ask opencode to describe a node to check its taint
- Ask opencode to get the payment-processor deployment yaml to check tolerations

### Level 3: The answer
The node has taint `processing=dedicated:NoSchedule` but the pod's toleration has effect `NoExecute` instead of `NoSchedule`. The effect must match exactly.

**Fix** (you can ask opencode to help):
- Change tolerations effect from "NoExecute" to "NoSchedule" in the payment-processor deployment

---

## Issue 3: order-service stuck in Init:0/2

### Level 1: Where to look
Check the logs for the order-service init container to see what it's waiting for.

### Level 2: Narrowing down
The init container runs `wget` against `payment-processor-svc` and waits for it to return healthy. Check if the `payment-processor-svc` service is working and has endpoints.

### Level 3: The answer
This is a **cascading failure**. The init container waits for `payment-processor-svc` to return healthy, but payment-processor can't start (Issue 2). **Fix Issue 2 first**, and this issue resolves automatically.

You do NOT need to modify order-service at all.

---

## Issue 4: inventory-service stuck in Init:CrashLoopBackOff

### Level 1: Where to look
Check the logs for the inventory-service init container to see why it's failing to read the configmap.

### Level 2: Narrowing down
Check if the inventory-config ConfigMap exists. If it does, the issue might be with RBAC permissions.

The pod isn't mounting the ConfigMap as a volume - it's reading it via the Kubernetes API. Check if the service account has permission to get configmaps.

### Level 3: The answer
The pod uses ServiceAccount `inventory-sa`. There's a Role and RoleBinding, but the RoleBinding references `inventory-service-sa` instead of `inventory-sa`.

**Fix** (you can ask opencode to help):
- Change the RoleBinding subject name from "inventory-service-sa" to "inventory-sa"

---

## Issue 5: notification-service is unreachable

### Level 1: Where to look
notification-service shows Running and Ready. The Service has endpoints. But can anything actually reach it through the Service?

### Level 2: Narrowing down
Traffic through the Service fails, but hitting the pod IP directly works. The problem is in how the Service routes traffic. Compare what the Service forwards to vs what the container actually listens on.

### Level 3: The answer
The Service `targetPort` is `9090` but the container listens on port `8080`. Traffic arrives at the Service on port 8080 and gets forwarded to container port 9090, where nothing is listening.

**Fix** (you can ask opencode to help):
- Change the targetPort from 9090 to 8080 in the notification-service service

---

## Issue 6: search-service keeps crashing (no errors in logs!)

### Level 1: Where to look
search-service is in CrashLoopBackOff. Check the logs to see if there are any error messages.

### Level 2: Narrowing down
If the logs show normal startup with no errors, the app isn't crashing itself - something is killing it. Check the pod events for probe failures.

Look for "Liveness probe failed" in the events. Then carefully examine the probe configuration - compare every field between the readiness and liveness probes.

### Level 3: The answer
The liveness probe checks port **8081** but the container listens on port **8080**. The readiness probe correctly uses 8080. The one-digit difference is easy to miss.

**Fix** (you can ask opencode to help):
- Change the livenessProbe.httpGet.port from 8081 to 8080 in the search-service deployment

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
The pod shows Running but 0/1 Ready. The service has no endpoints. Check the pod events for probe failure messages.

### Level 2: Narrowing down
The events show a readiness probe failing. Check what path the probe is checking and what path the app actually serves.

Then test what the app actually responds to.

### Level 3: The answer
The readiness probe checks `/ready` but the app only serves `/health`. The `/ready` path returns 404, so the probe always fails and the pod is never marked Ready.

**Fix** (you can ask opencode to help):
- Change the readinessProbe.httpGet.path from "/ready" to "/health" in the recommendation-service deployment

---

## Issue 8: analytics-service won't start (secret key error)

> **Prerequisite**: You must fix Issue 1 (quota) first before this error becomes visible. Once the pod can be created, it will show `CreateContainerConfigError`.

### Level 1: Where to look
Check if analytics-service pods are being created. If not, describe the pod to see the error.

The error is `CreateContainerConfigError`. This usually means a missing Secret or ConfigMap.

### Level 2: Narrowing down
Check if the analytics-credentials Secret exists. If it does, compare the key names in the Secret vs what the pod expects.

### Level 3: The answer
The Secret has key `api-key` but the pod's `secretKeyRef` expects key `API_KEY`. Kubernetes key names are case-sensitive and hyphen vs underscore matters.

**Fix** (you can ask opencode to help):
- Change the secretKeyRef.key from "API_KEY" to "api-key" in the analytics-service deployment

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
