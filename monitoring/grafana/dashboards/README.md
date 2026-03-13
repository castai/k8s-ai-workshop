# Grafana Dashboards

This directory contains pre-built Grafana dashboards for the Kubernetes workshop.

## Available Dashboards

The kube-prometheus-stack includes several default dashboards out-of-the-box:

### Default Dashboards (Automatically Included)

1. **Kubernetes / Compute Resources / Cluster**
   - Overall cluster resource usage
   - CPU, memory, network across all nodes
   - Request vs. usage comparison

2. **Kubernetes / Compute Resources / Namespace (Pods)**
   - Pod-level resource usage per namespace
   - Useful for riddle analysis

3. **Kubernetes / Compute Resources / Node (Pods)**
   - Pod distribution across nodes
   - Node resource pressure

4. **Kubernetes / Compute Resources / Pod**
   - Individual pod metrics
   - Container CPU, memory, network usage

5. **Kubernetes / Networking / Cluster**
   - Network bandwidth and packet rates
   - Useful for understanding service communication

6. **Node Exporter / Nodes**
   - Detailed node metrics (CPU, memory, disk, network)
   - Hardware-level monitoring

## Accessing Dashboards

1. Open Grafana: http://localhost:30091
2. Login: `admin` / `admin`
3. Navigate to **Dashboards** → **Browse**
4. Look for dashboards in the "General" or "Kubernetes" folders

## Custom Dashboards

You can import custom dashboards by:

1. Going to **Dashboards** → **Import**
2. Enter a dashboard ID from [grafana.com/grafana/dashboards](https://grafana.com/grafana/dashboards/)
3. Select the Prometheus data source

### Recommended Dashboard IDs

- **13770**: Kubernetes Cluster (Prometheus)
- **15760**: Kubernetes / Views / Pods
- **15758**: Kubernetes / System / API Server
- **15757**: Kubernetes / System / CoreDNS
- **12114**: Kubernetes Resource Requests

## Using Dashboards in Riddles

### Riddle 1: Cluster Debugging
- Use **Kubernetes / Compute Resources / Namespace (Pods)**
- Filter by namespace: `riddle-1`
- Look for pod restarts, OOMKills, and resource issues

### Riddle 2: Workload Autoscaling
- Use **Kubernetes / Compute Resources / Pod**
- Monitor memory usage approaching limits
- Watch HPA scaling events in pod count

### Riddle 3: End-to-End Optimization
- Use **Kubernetes / Compute Resources / Cluster**
- Compare resource requests vs. actual usage
- Identify over-provisioned workloads

## PromQL Queries

Useful Prometheus queries for the workshop:

### Pod Memory Usage
```promql
container_memory_usage_bytes{namespace="riddle-3", container!=""}
```

### Pod CPU Usage
```promql
rate(container_cpu_usage_seconds_total{namespace="riddle-3", container!=""}[5m])
```

### Resource Requests vs. Usage
```promql
sum(kube_pod_container_resource_requests{namespace="riddle-3", resource="memory"})
```

### OOMKill Events
```promql
kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}
```

### Pod Restart Count
```promql
kube_pod_container_status_restarts_total{namespace="riddle-3"}
```

## Creating Custom Dashboards

To create a custom dashboard as a ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: custom-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  custom-dashboard.json: |
    {
      "dashboard": { ... },
      "overwrite": true
    }
```

Apply with:
```bash
kubectl apply -f custom-dashboard.yaml
```

Grafana sidecar will automatically load dashboards with the `grafana_dashboard: "1"` label.

## Troubleshooting

### Dashboards Not Showing Data

1. Check Prometheus is scraping metrics:
   - Open http://localhost:30090
   - Go to **Status** → **Targets**
   - Verify all targets are "UP"

2. Check data source in Grafana:
   - Go to **Configuration** → **Data Sources**
   - Click on "Prometheus"
   - Click "Test" - should see "Data source is working"

3. Verify metrics exist:
   - In Prometheus, go to **Graph**
   - Try query: `up{job="kubelet"}`
   - Should return results

### Dashboard Import Fails

1. Ensure dashboard JSON is valid
2. Check that data source name matches ("Prometheus")
3. Try importing via URL instead of JSON

---

**Next**: Explore [riddle-specific metrics](../../riddles/README.md) to understand what to monitor in each challenge.
