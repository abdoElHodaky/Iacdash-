# 📊 Monitoring & Observability

Complete guide for implementing observability with Grafana, Prometheus, Loki, and Tempo.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Prometheus Setup](#prometheus-setup)
- [Grafana Configuration](#grafana-configuration)
- [Loki for Logs](#loki-for-logs)
- [Tempo for Tracing](#tempo-for-tracing)
- [ServiceMonitors](#servicemonitors)
- [Alerting](#alerting)
- [Dashboards](#dashboards)
- [Best Practices](#best-practices)

---

## Overview

The observability stack provides three pillars:

- **Metrics** (Prometheus): Time-series data, resource usage, request rates
- **Logs** (Loki): Structured and unstructured log data
- **Traces** (Tempo): Distributed request tracing

### Architecture

```
┌─────────────────────────────────────────────┐
│              Applications                    │
│  • Gateway API                               │
│  • Service Mesh                              │
│  • Microservices                             │
└──┬────────┬────────────┬─────────────────────┘
   │        │            │
   │Metrics │Logs        │Traces
   │        │            │
┌──▼────┐ ┌─▼──────┐ ┌──▼──────┐
│Promethe│ │  Loki  │ │  Tempo  │
│  us    │ │        │ │         │
└──┬─────┘ └─┬──────┘ └──┬──────┘
   │         │           │
   └────────▼────────────┘
            │
   ┌────────▼─────────┐
   │     Grafana      │
   │  • Dashboards    │
   │  • Alerts        │
   │  • Queries       │
   └──────────────────┘
```

---

## Prometheus Setup

### Install with Helm

```bash
# Add Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create namespace
kubectl create namespace monitoring

# Install kube-prometheus-stack
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.retention=30d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=50Gi \
  --set grafana.adminPassword='SecurePassword123!' \
  --set grafana.persistence.enabled=true \
  --set grafana.persistence.size=10Gi

# Verify installation
kubectl get pods -n monitoring
kubectl get servicemonitors -A
```

### Custom Values File

```yaml
# monitoring/prometheus-values.yaml
prometheus:
  prometheusSpec:
    # Retention
    retention: 30d
    retentionSize: "45GB"
    
    # Storage
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 50Gi
    
    # Resources
    resources:
      requests:
        cpu: 500m
        memory: 2Gi
      limits:
        cpu: 2000m
        memory: 8Gi
    
    # Scrape config
    scrapeInterval: 30s
    scrapeTimeout: 10s
    evaluationInterval: 30s
    
    # Service monitor selector
    serviceMonitorSelectorNilUsesHelmValues: false
    
    # Additional scrape configs
    additionalScrapeConfigs:
    - job_name: 'istio-mesh'
      kubernetes_sd_configs:
      - role: endpoints
        namespaces:
          names:
          - istio-system
    
    # External labels
    externalLabels:
      cluster: production
      environment: prod
      region: us-east-1
    
    # Remote write (optional - for long-term storage)
    remoteWrite:
    - url: https://prometheus-prod.example.com/api/v1/write
      basicAuth:
        username:
          name: prometheus-remote-write
          key: username
        password:
          name: prometheus-remote-write
          key: password

grafana:
  adminPassword: ${GRAFANA_ADMIN_PASSWORD}
  
  # Persistence
  persistence:
    enabled: true
    size: 10Gi
  
  # Resources
  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      cpu: 500m
      memory: 1Gi
  
  # Ingress
  ingress:
    enabled: true
    ingressClassName: istio
    hosts:
    - grafana.example.com
    tls:
    - secretName: grafana-tls
      hosts:
      - grafana.example.com

alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi
    
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 256Mi
```

### Deploy with Custom Values

```bash
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values monitoring/prometheus-values.yaml
```

---

## Grafana Configuration

### Access Grafana

```bash
# Port forward
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Get admin password
kubectl get secret -n monitoring prometheus-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode

# Access: http://localhost:3000
# Username: admin
# Password: <from above>
```

### Add Data Sources

```yaml
# monitoring/grafana-datasources.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasources
  namespace: monitoring
  labels:
    grafana_datasource: "1"
data:
  datasources.yaml: |
    apiVersion: 1
    datasources:
    # Prometheus
    - name: Prometheus
      type: prometheus
      access: proxy
      url: http://prometheus-kube-prometheus-prometheus.monitoring:9090
      isDefault: true
      editable: false
    
    # Loki
    - name: Loki
      type: loki
      access: proxy
      url: http://loki.monitoring:3100
      jsonData:
        maxLines: 1000
    
    # Tempo
    - name: Tempo
      type: tempo
      access: proxy
      url: http://tempo.monitoring:3100
      jsonData:
        tracesToLogs:
          datasourceUid: 'loki'
          tags: ['job', 'instance', 'pod', 'namespace']
          mappedTags: [{ key: 'service.name', value: 'service' }]
        lokiSearch:
          datasourceUid: 'loki'
        serviceMap:
          datasourceUid: 'prometheus'
```

---

## Loki for Logs

### Install Loki

```bash
# Add Grafana Helm repo
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install Loki stack (includes Promtail)
helm install loki grafana/loki-stack \
  --namespace monitoring \
  --set loki.persistence.enabled=true \
  --set loki.persistence.size=50Gi \
  --set promtail.enabled=true \
  --set grafana.enabled=false

# Verify
kubectl get pods -n monitoring | grep loki
```

### Loki Configuration

```yaml
# monitoring/loki-values.yaml
loki:
  persistence:
    enabled: true
    size: 50Gi
  
  config:
    auth_enabled: false
    
    ingester:
      chunk_idle_period: 3m
      chunk_block_size: 262144
      chunk_retain_period: 1m
      max_transfer_retries: 0
      lifecycler:
        ring:
          kvstore:
            store: inmemory
          replication_factor: 1
    
    limits_config:
      enforce_metric_name: false
      reject_old_samples: true
      reject_old_samples_max_age: 168h
      ingestion_rate_mb: 10
      ingestion_burst_size_mb: 20
    
    schema_config:
      configs:
      - from: 2020-10-24
        store: boltdb-shipper
        object_store: filesystem
        schema: v11
        index:
          prefix: index_
          period: 24h
    
    server:
      http_listen_port: 3100
    
    storage_config:
      boltdb_shipper:
        active_index_directory: /data/loki/boltdb-shipper-active
        cache_location: /data/loki/boltdb-shipper-cache
        cache_ttl: 24h
        shared_store: filesystem
      filesystem:
        directory: /data/loki/chunks
    
    chunk_store_config:
      max_look_back_period: 0s
    
    table_manager:
      retention_deletes_enabled: true
      retention_period: 168h

promtail:
  enabled: true
  
  config:
    clients:
    - url: http://loki:3100/loki/api/v1/push
    
    scrapeConfigs:
    # Kubernetes pods
    - job_name: kubernetes-pods
      kubernetes_sd_configs:
      - role: pod
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_node_name]
        target_label: node_name
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod
      - source_labels: [__meta_kubernetes_pod_container_name]
        target_label: container
      - source_labels: [__meta_kubernetes_pod_label_app]
        target_label: app
      - source_labels: [__meta_kubernetes_pod_label_version]
        target_label: version
```

### Query Logs in Grafana

```promql
# All logs from namespace
{namespace="default"}

# Logs from specific app
{app="api-service"}

# Filter by log level
{app="api-service"} |= "ERROR"

# JSON parsing
{app="api-service"} | json | level="error"

# Rate of errors
rate({app="api-service"} |= "ERROR" [5m])
```

---

## Tempo for Tracing

### Install Tempo

```bash
# Install Tempo
helm install tempo grafana/tempo \
  --namespace monitoring \
  --set tempo.storage.trace.backend=local \
  --set persistence.enabled=true \
  --set persistence.size=10Gi

# Verify
kubectl get pods -n monitoring | grep tempo
```

### Tempo Configuration

```yaml
# monitoring/tempo-values.yaml
tempo:
  repository: grafana/tempo
  tag: latest
  pullPolicy: IfNotPresent
  
  storage:
    trace:
      backend: local
      local:
        path: /var/tempo/traces
  
  receivers:
    jaeger:
      protocols:
        thrift_http:
        grpc:
    zipkin:
    otlp:
      protocols:
        http:
        grpc:
  
  config: |
    server:
      http_listen_port: 3200
    
    distributor:
      receivers:
        jaeger:
          protocols:
            thrift_http:
            grpc:
        zipkin:
        otlp:
          protocols:
            http:
            grpc:
    
    ingester:
      trace_idle_period: 10s
      max_block_bytes: 1_000_000
      max_block_duration: 5m
    
    compactor:
      compaction:
        compaction_window: 1h
        max_compaction_objects: 1000000
        block_retention: 48h
        compacted_block_retention: 1h
    
    storage:
      trace:
        backend: local
        wal:
          path: /var/tempo/wal
        local:
          path: /var/tempo/blocks
    
    querier:
      frontend_worker:
        frontend_address: tempo-query-frontend:9095

persistence:
  enabled: true
  size: 10Gi
```

### Enable Tracing in Istio

```yaml
# service-mesh/istio/tracing.yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  name: istio-with-tracing
  namespace: istio-system
spec:
  meshConfig:
    enableTracing: true
    defaultConfig:
      tracing:
        sampling: 100.0
        zipkin:
          address: tempo.monitoring:9411
```

---

## ServiceMonitors

### Gateway API ServiceMonitor

```yaml
# monitoring/servicemonitors/gateway-monitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: gateway-metrics
  namespace: monitoring
  labels:
    app: gateway
spec:
  selector:
    matchLabels:
      app: istio-ingressgateway
  
  namespaceSelector:
    matchNames:
    - istio-system
  
  endpoints:
  - port: http-envoy-prom
    interval: 30s
    path: /stats/prometheus
    relabelings:
    - sourceLabels: [__meta_kubernetes_pod_name]
      targetLabel: pod
    - sourceLabels: [__meta_kubernetes_namespace]
      targetLabel: namespace
```

### Application ServiceMonitor

```yaml
# monitoring/servicemonitors/app-monitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: api-service-metrics
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: api-service
  
  namespaceSelector:
    matchNames:
    - default
  
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
    
    # Metric relabeling
    metricRelabelings:
    - sourceLabels: [__name__]
      regex: 'go_.*'
      action: drop
    
    # Add custom labels
    relabelings:
    - sourceLabels: [__meta_kubernetes_pod_label_version]
      targetLabel: version
    - sourceLabels: [__meta_kubernetes_pod_node_name]
      targetLabel: node
```

### Service Mesh ServiceMonitor

```yaml
# monitoring/servicemonitors/istio-monitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: istio-component-monitor
  namespace: monitoring
spec:
  jobLabel: istio
  targetLabels: [app]
  selector:
    matchExpressions:
    - {key: istio, operator: In, values: [pilot]}
  namespaceSelector:
    any: true
  endpoints:
  - port: http-monitoring
    interval: 15s
```

---

## Alerting

### Prometheus Rules

```yaml
# monitoring/alerts/gateway-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: gateway-alerts
  namespace: monitoring
  labels:
    prometheus: kube-prometheus
spec:
  groups:
  - name: gateway.rules
    interval: 30s
    rules:
    # High error rate
    - alert: GatewayHighErrorRate
      expr: |
        sum(rate(istio_requests_total{response_code=~"5.."}[5m])) 
        / 
        sum(rate(istio_requests_total[5m])) 
        > 0.05
      for: 5m
      labels:
        severity: critical
        component: gateway
      annotations:
        summary: "Gateway error rate above 5%"
        description: "{{ $labels.destination_service }} error rate is {{ $value | humanizePercentage }}"
        runbook_url: "https://wiki.example.com/runbooks/gateway-high-error-rate"
    
    # High latency
    - alert: GatewayHighLatency
      expr: |
        histogram_quantile(0.95, 
          sum(rate(istio_request_duration_milliseconds_bucket[5m])) by (le, destination_service)
        ) > 500
      for: 5m
      labels:
        severity: warning
        component: gateway
      annotations:
        summary: "Gateway P95 latency above 500ms"
        description: "{{ $labels.destination_service }} P95 latency is {{ $value }}ms"
    
    # Gateway down
    - alert: GatewayDown
      expr: up{job="istio-ingressgateway"} == 0
      for: 1m
      labels:
        severity: critical
        component: gateway
      annotations:
        summary: "Gateway is down"
        description: "Gateway {{ $labels.instance }} has been down for more than 1 minute"
    
    # Certificate expiring
    - alert: CertificateExpiringSoon
      expr: |
        (cert_manager_certificate_expiration_timestamp_seconds - time()) / 86400 < 14
      for: 1h
      labels:
        severity: warning
        component: gateway
      annotations:
        summary: "Certificate expiring in less than 14 days"
        description: "Certificate {{ $labels.name }} expires in {{ $value }} days"
```

### Application Alerts

```yaml
# monitoring/alerts/app-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: app-alerts
  namespace: monitoring
spec:
  groups:
  - name: application.rules
    interval: 30s
    rules:
    # Pod crash loop
    - alert: PodCrashLooping
      expr: rate(kube_pod_container_status_restarts_total[15m]) > 0
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Pod {{ $labels.namespace }}/{{ $labels.pod }} is crash looping"
        description: "Pod has restarted {{ $value }} times in the last 15 minutes"
    
    # High memory usage
    - alert: HighMemoryUsage
      expr: |
        (container_memory_working_set_bytes / container_spec_memory_limit_bytes) > 0.9
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Container memory usage above 90%"
        description: "{{ $labels.namespace }}/{{ $labels.pod }}/{{ $labels.container }} is using {{ $value | humanizePercentage }} of memory limit"
    
    # High CPU usage
    - alert: HighCPUUsage
      expr: |
        rate(container_cpu_usage_seconds_total[5m]) > 0.9
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "Container CPU usage above 90%"
        description: "{{ $labels.namespace }}/{{ $labels.pod }}/{{ $labels.container }} CPU usage is {{ $value | humanizePercentage }}"
```

### Alertmanager Configuration

```yaml
# monitoring/alertmanager-config.yaml
apiVersion: v1
kind: Secret
metadata:
  name: alertmanager-prometheus-kube-prometheus-alertmanager
  namespace: monitoring
type: Opaque
stringData:
  alertmanager.yaml: |
    global:
      resolve_timeout: 5m
      slack_api_url: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'
    
    route:
      group_by: ['alertname', 'cluster', 'namespace']
      group_wait: 10s
      group_interval: 10s
      repeat_interval: 12h
      receiver: 'default'
      
      routes:
      # Critical alerts to PagerDuty
      - match:
          severity: critical
        receiver: 'pagerduty'
        continue: true
      
      # All alerts to Slack
      - match_re:
          severity: warning|critical
        receiver: 'slack'
    
    receivers:
    - name: 'default'
      slack_configs:
      - channel: '#alerts'
        title: '{{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
    
    - name: 'slack'
      slack_configs:
      - channel: '#alerts'
        send_resolved: true
        title: |-
          [{{ .Status | toUpper }}{{ if eq .Status "firing" }}:{{ .Alerts.Firing | len }}{{ end }}] {{ .CommonLabels.alertname }}
        text: >-
          {{ range .Alerts -}}
          *Alert:* {{ .Annotations.summary }}
          *Description:* {{ .Annotations.description }}
          *Details:*
            {{ range .Labels.SortedPairs }} • *{{ .Name }}:* `{{ .Value }}`
            {{ end }}
          {{ end }}
    
    - name: 'pagerduty'
      pagerduty_configs:
      - service_key: 'YOUR_PAGERDUTY_KEY'
        description: '{{ .GroupLabels.alertname }}'
```

---

## Dashboards

### Gateway Performance Dashboard

```json
{
  "dashboard": {
    "title": "Gateway API Performance",
    "panels": [
      {
        "title": "Request Rate",
        "targets": [{
          "expr": "sum(rate(istio_requests_total[5m])) by (destination_service)"
        }]
      },
      {
        "title": "P95 Latency",
        "targets": [{
          "expr": "histogram_quantile(0.95, sum(rate(istio_request_duration_milliseconds_bucket[5m])) by (le, destination_service))"
        }]
      },
      {
        "title": "Error Rate",
        "targets": [{
          "expr": "sum(rate(istio_requests_total{response_code=~\"5..\"}[5m])) / sum(rate(istio_requests_total[5m]))"
        }]
      }
    ]
  }
}
```

### Import Community Dashboards

```bash
# Gateway API Dashboard
Dashboard ID: 15474

# Istio Performance
Dashboard ID: 7636

# Kubernetes Cluster Monitoring
Dashboard ID: 7249

# Node Exporter Full
Dashboard ID: 1860
```

---

## Best Practices

### 1. Metrics Collection

✅ **DO:**
- Use ServiceMonitors for automatic discovery
- Set appropriate scrape intervals (15-30s)
- Add relabeling for better organization
- Monitor metric cardinality

❌ **DON'T:**
- Scrape too frequently (< 10s)
- Create high-cardinality labels
- Expose sensitive data in metrics
- Skip metric documentation

### 2. Log Management

✅ **DO:**
- Use structured logging (JSON)
- Add correlation IDs
- Set appropriate retention (7-30 days)
- Index important fields

❌ **DON'T:**
- Log sensitive data
- Create excessive log volume
- Skip log rotation
- Use string concatenation

### 3. Alerting

✅ **DO:**
- Alert on symptoms, not causes
- Use meaningful alert names
- Include runbook links
- Test alert routing

❌ **DON'T:**
- Create alert storms
- Alert on non-actionable metrics
- Skip alert documentation
- Ignore flapping alerts

### 4. Dashboard Design

✅ **DO:**
- Start with high-level overview
- Use consistent time ranges
- Add descriptions
- Include SLO indicators

❌ **DON'T:**
- Overload with panels
- Use pie charts for time-series
- Skip variable templates
- Hardcode values

---

**Next Steps:**
- Implement security: [SECURITY.md](SECURITY.md)
- Troubleshooting guide: [TROUBLESHOOTING.md](TROUBLESHOOTING.md)