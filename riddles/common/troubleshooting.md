# Workshop Troubleshooting Guide

Common issues and solutions for the Kubernetes AI-Powered Operations Workshop.


## Riddle-Specific Issues

### Riddle 1: Debugging

#### Pods Still Failing After Fixes

You can use opencode to help investigate:
- Ask opencode to get an overview of all pods in riddle-1
- Ask opencode to check events for errors sorted by timestamp
- Ask opencode to verify service endpoints exist

#### API Gateway Not Accessible

You can ask opencode to help with:
- Checking service endpoints for api-gateway
- Verifying the NodePort configuration
- Trying port-forward to access the service
- Checking if the api-gateway pod is Running

### Riddle 2: Scaling Under Pressure

#### HPA Shows "unknown" Metrics

**Symptoms**: HPA shows `<unknown>` for targets

You can ask opencode to help with:
- Checking if metrics-server is working by running top commands
- Verifying resource requests are defined on the deployment
- Getting HPA status to see if metrics have populated
- Describing HPA to check conditions

#### HPA Not Scaling

**Symptoms**: Pod count doesn't change under load

You can ask opencode to help with:
- Checking HPA status and events
- Verifying if load is actually high
- Checking HPA events
- Checking if resource requests are realistic (very low requests cause HPA to compute absurdly high utilization percentages)

### Riddle 3: The Slow Burn

#### Pods Keep Restarting

**Symptoms**: Pods cycle between Running and OOMKilled with increasing restart counts

You can ask opencode to help with:
- Checking pod status and restart counts
- Checking the termination reason from pod description
- Watching memory usage over time
- Checking current resource configuration for the stress-app deployment

#### Fix Applied But Pods Still OOMKilling

**Symptoms**: Changed resource values but pods still crash

You can ask opencode to help with:
- Verifying the new values actually took effect
- Waiting for rollout to complete
- Watching pods for at least 2-3 minutes to cover the full usage cycle

## AI Integration Issues

### MCP Servers Not Working

**Symptoms**: AI agent says "I don't have access to kubectl" or no tools appear

**Solutions**:
```bash
# Check MCP server status
opencode mcp list

# Verify config
cat ~/.config/opencode/opencode.json | python3 -m json.tool

# Re-run setup
./riddles/common/setup-opencode.sh

# Check npx is available
npx --version
```

### Wrong Kubernetes Context

**Symptoms**: AI accessing wrong cluster or no access

**Solutions**:
```bash
# Check current context
kubectl config current-context

# Switch to workshop cluster
kubectl config use-context kind-workshop-cluster

# Re-run setup to update KUBECONFIG
./riddles/common/setup-opencode.sh
```

## Network / Access Issues

### Can't Access NodePort Services

**Symptoms**: `curl http://localhost:30000` fails

**Solutions**:
```bash
# Check if port is mapped in kind
docker ps | grep workshop-cluster

# Verify service exists
kubectl get svc -A | grep NodePort

# Check pod is running
kubectl get pods -A

# Try port-forward instead
kubectl port-forward -n <namespace> svc/<service> 8080:8080
curl http://localhost:8080
```

### DNS Resolution Fails

**Symptoms**: Services can't reach each other

**Solutions**:
```bash
# Check CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Test DNS from pod
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes

# Check service endpoints
kubectl get endpoints -n <namespace>
```

## Performance Issues

### Cluster Running Slow

**Solutions**:
```bash
# Check node resources
kubectl top nodes

# Check pod resource usage
kubectl top pods -A

# Look for resource pressure
kubectl describe nodes | grep -A 5 Conditions

# If memory/CPU exhausted:
# - Delete unnecessary namespaces
# - Reduce replica counts
# - Increase Docker resources
```

### Pods Taking Long to Start

**Solutions**:
```bash
# Check if images are being pulled
kubectl describe pod <pod> -n <namespace> | grep -A 10 Events

# Pre-pull images on all nodes
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: image-puller
spec:
  selector:
    matchLabels:
      app: image-puller
  template:
    metadata:
      labels:
        app: image-puller
    spec:
      initContainers:
      - name: pull-images
        image: gcr.io/google-samples/microservices-demo/frontend:v0.8.0
        command: ['sh', '-c', 'echo done']
      containers:
      - name: pause
        image: gcr.io/pause:3.9
EOF
```

## Complete Cluster Reset

If all else fails, reset everything:

```bash
# Delete cluster
kind delete cluster --name workshop-cluster

# Clean Docker
docker system prune -a -f

# Restart Docker Desktop

# Recreate everything
./setup/install-kind.sh
./setup/verify-setup.sh
./setup/install-monitoring.sh
```

## Getting Additional Help

### Collect Diagnostic Information

```bash
# Create diagnostic report
kubectl cluster-info dump > cluster-info.txt

# Get all pod statuses
kubectl get pods -A > pods-status.txt

# Get events
kubectl get events -A --sort-by='.lastTimestamp' > events.txt

# Check Docker
docker info > docker-info.txt
```

### Useful Debug Commands

```bash
# Check API server
kubectl get --raw /healthz

# Check component status
kubectl get componentstatuses

# List all API resources
kubectl api-resources

# Check RBAC
kubectl auth can-i '*' '*' --all-namespaces

# Verify DNS
kubectl run -it --rm debug --image=busybox --restart=Never -- sh
# Inside pod:
nslookup kubernetes
nslookup google.com
```

## Common Error Messages

| Error | Meaning | Solution |
|-------|---------|----------|
| `ImagePullBackOff` | Can't pull container image | Check image name/tag, internet connection |
| `CrashLoopBackOff` | Container keeps crashing | Check logs: `kubectl logs <pod> --previous` |
| `CreateContainerConfigError` | Missing config/secret | Create missing resource |
| `OOMKilled` | Out of memory | Increase memory limits |
| `Pending` | Can't schedule pod | Check resources, node selectors |
| `Error: unknown` (HPA) | No metrics available | Wait for metrics-server, check resource requests |

## Prevention Tips

1. **Always verify before applying**:
   ```bash
   kubectl apply -f manifest.yaml --dry-run=client
   ```

2. **Use namespace isolation**:
   - Don't mix riddles in same namespace

3. **Monitor resources**:
   ```bash
   watch kubectl top nodes
   watch kubectl top pods -A
   ```

4. **Keep Docker healthy**:
   - Regularly prune: `docker system prune`
   - Monitor Docker Desktop resource usage
   - Restart Docker if sluggish

5. **Check logs early**:
   - `kubectl logs` at first sign of trouble
   - `kubectl describe` shows events
   - `kubectl get events` shows history

---

**Still stuck?** Check the workshop README or ask the instructor for help!
