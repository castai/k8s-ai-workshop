# Workshop Troubleshooting Guide

Common issues and solutions for the Kubernetes AI-Powered Operations Workshop.

## Cluster Setup Issues

### kind Cluster Won't Start

**Symptoms**: `Error: failed to create cluster`

**Solutions**:
```bash
# Check Docker is running
docker info

# Delete existing cluster
kind delete cluster --name workshop-cluster

# Clean up Docker
docker container prune -f
docker volume prune -f

# Recreate cluster
./setup/install-kind.sh
```

### Insufficient Docker Resources

**Symptoms**: Pods stuck in Pending, nodes show MemoryPressure

**Solutions**:
1. Open Docker Desktop → Settings → Resources
2. Increase Memory to 12-16GB
3. Increase CPU to 6-8 cores
4. Restart Docker Desktop
5. Recreate cluster

### Nodes Not Ready

**Symptoms**: `kubectl get nodes` shows NotReady

**Solutions**:
```bash
# Check node details
kubectl describe nodes

# Check system pods
kubectl get pods -n kube-system

# If CNI issue, restart kind
kind delete cluster --name workshop-cluster
./setup/install-kind.sh
```

## Monitoring Stack Issues

### metrics-server Not Working

**Symptoms**: `kubectl top nodes` returns error

**Solutions**:
```bash
# Check metrics-server pods
kubectl get pods -n kube-system -l k8s-app=metrics-server

# Check logs
kubectl logs -n kube-system -l k8s-app=metrics-server

# Reinstall
helm delete metrics-server -n kube-system
./setup/install-monitoring.sh

# Wait 60 seconds for metrics to populate
sleep 60
kubectl top nodes
```

### Prometheus Not Accessible

**Symptoms**: http://localhost:30090 not responding

**Solutions**:
```bash
# Check Prometheus pods
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus

# Check service
kubectl get svc -n monitoring | grep prometheus

# Verify NodePort
kubectl get svc prometheus-kube-prometheus-prometheus -n monitoring -o yaml | grep nodePort

# Port forward as alternative
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Access http://localhost:9090
```

### Grafana Login Issues

**Symptoms**: Can't log into Grafana

**Default credentials**:
- Username: `admin`
- Password: `admin`

**If default doesn't work**:
```bash
# Get Grafana admin password
kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 --decode

# Reset password
kubectl delete secret -n monitoring prometheus-grafana
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.adminPassword=admin \
  --reuse-values
```

## Riddle-Specific Issues

### Riddle 1: Debugging

#### Pods Still Failing After Fixes

**Check**:
```bash
# Get an overview of all pods
kubectl get pods -n riddle-1

# Check events for errors
kubectl get events -n riddle-1 --sort-by='.lastTimestamp'

# Verify service endpoints exist
kubectl get endpoints -n riddle-1
```

#### API Gateway Not Accessible

**Solutions**:
```bash
# Check service endpoints
kubectl get endpoints -n riddle-1 api-gateway

# Verify NodePort
kubectl get svc api-gateway -n riddle-1

# Try port-forward
kubectl port-forward -n riddle-1 svc/api-gateway 8080:8080
curl http://localhost:8080

# Check if the pod is Running
kubectl get pods -n riddle-1 -l app=api-gateway
```

### Riddle 2: Scaling Under Pressure

#### HPA Shows "unknown" Metrics

**Symptoms**: `kubectl get hpa` shows `<unknown>` for targets

**Solutions**:
```bash
# Check metrics-server is working
kubectl top nodes
kubectl top pods -n riddle-2

# Verify resource requests are defined on the deployment
kubectl get deployment web-frontend -n riddle-2 -o yaml | grep -A 5 resources

# Wait for metrics to populate (60 seconds after creating HPA)
kubectl get hpa -n riddle-2

# Check HPA conditions
kubectl describe hpa -n riddle-2
```

#### HPA Not Scaling

**Symptoms**: Pod count doesn't change under load

**Solutions**:
```bash
# Check HPA status and events
kubectl describe hpa -n riddle-2

# Verify load is actually high
kubectl top pods -n riddle-2

# Check HPA events
kubectl get events -n riddle-2 | grep -i hpa

# Check if resource requests are realistic — very low requests
# cause HPA to compute absurdly high utilization percentages
kubectl get deployment web-frontend -n riddle-2 -o yaml | grep -A 5 resources
```

### Riddle 3: The Slow Burn

#### Pods Keep Restarting

**Symptoms**: Pods cycle between Running and OOMKilled with increasing restart counts

**Solutions**:
```bash
# Check pod status and restart counts
kubectl get pods -n riddle-3

# Check the termination reason
kubectl describe pod -l app=stress-app -n riddle-3

# Watch memory usage over time (run multiple times)
kubectl top pods -n riddle-3

# Check current resource configuration
kubectl get deployment stress-app -n riddle-3 -o yaml | grep -A 8 resources
```

#### Fix Applied But Pods Still OOMKilling

**Symptoms**: Changed resource values but pods still crash

**Solutions**:
```bash
# Verify the new values actually took effect
kubectl get deployment stress-app -n riddle-3 -o yaml | grep -A 8 resources

# Wait for rollout to complete
kubectl rollout status deployment/stress-app -n riddle-3

# Watch pods for at least 2-3 minutes to cover the full usage cycle
kubectl get pods -n riddle-3 -w
```

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
