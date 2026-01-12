# 📋 Development & Deployment Standards

Comprehensive standards and conventions for maintaining consistency, security, and reliability across the Gateway API and Service Mesh platform.

---

## 🏷️ **Naming Conventions**

### **Resource Naming**

#### **Kubernetes Resources**
```yaml
# Pattern: <purpose>-<component>-<environment>
# Examples:
metadata:
  name: api-gateway-production
  name: user-service-staging
  name: database-secret-dev
```

#### **Namespace Naming**
```yaml
# Pattern: <environment>-<team>-<purpose> or <purpose>-<environment>
# Examples:
- production-platform-core
- staging-api-services
- dev-frontend-apps
- monitoring
- istio-system
- cert-manager
```

#### **Label Standards**
```yaml
# Required labels for all resources
metadata:
  labels:
    app.kubernetes.io/name: "user-service"
    app.kubernetes.io/instance: "user-service-prod"
    app.kubernetes.io/version: "v1.2.3"
    app.kubernetes.io/component: "backend"
    app.kubernetes.io/part-of: "user-management"
    app.kubernetes.io/managed-by: "flux"
    
    # Environment-specific labels
    environment: "production"
    tier: "backend"
    team: "platform"
    cost-center: "engineering"
    
    # Security labels
    security.istio.io/tlsMode: "istio"
    network-policy: "restricted"
```

#### **Annotation Standards**
```yaml
metadata:
  annotations:
    # Deployment information
    deployment.kubernetes.io/revision: "3"
    kubectl.kubernetes.io/last-applied-configuration: "..."
    
    # Monitoring annotations
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/metrics"
    
    # Security annotations
    seccomp.security.alpha.kubernetes.io/pod: "runtime/default"
    
    # Backup annotations
    backup.velero.io/backup-volumes: "data"
    
    # Certificate annotations
    cert-manager.io/cluster-issuer: "letsencrypt-production"
    
    # Documentation
    description: "User management service API"
    documentation: "https://docs.example.com/user-service"
    contact: "platform-team@example.com"
```

### **File and Directory Naming**

#### **Repository Structure**
```
├── flux/                          # FluxCD configurations
│   ├── clusters/                  # Cluster-specific configs
│   │   ├── dev/
│   │   ├── staging/
│   │   └── production/
│   └── infrastructure/            # Shared infrastructure
├── terraform/                     # Infrastructure as Code
│   ├── modules/                   # Reusable modules
│   └── examples/                  # Usage examples
├── gateway-api/                   # Gateway API configurations
├── service-mesh/                  # Istio configurations
├── monitoring/                    # Observability configs
├── security/                      # Security configurations
├── transformations/               # Traffic transformations
├── scripts/                       # Operational scripts
└── docs/                         # Documentation
```

#### **File Naming Patterns**
```bash
# Kubernetes manifests
<resource-type>-<name>-<environment>.yaml
# Examples:
deployment-user-service-production.yaml
service-api-gateway-staging.yaml
configmap-app-config-dev.yaml

# Terraform files
<provider>-<resource>.tf
# Examples:
aws-eks-cluster.tf
gcp-gke-cluster.tf
variables.tf
outputs.tf

# Scripts
<action>-<target>.sh
# Examples:
backup-cluster.sh
deploy-application.sh
debug-networking.sh
```

---

## 🔐 **Security Standards**

### **Container Security**

#### **Security Contexts**
```yaml
# Pod security context (required for all pods)
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
    supplementalGroups: [1000]

  containers:
  - name: app
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
        - ALL
        add:
        - NET_BIND_SERVICE  # Only if needed
      readOnlyRootFilesystem: true
      runAsNonRoot: true
      runAsUser: 1000
      runAsGroup: 1000
```

#### **Resource Limits (Required)**
```yaml
spec:
  containers:
  - name: app
    resources:
      requests:
        cpu: "100m"
        memory: "128Mi"
      limits:
        cpu: "500m"
        memory: "512Mi"
        ephemeral-storage: "1Gi"
```

#### **Network Policies (Required for Production)**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-app-traffic
spec:
  podSelector:
    matchLabels:
      app: user-service
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: api-gateway
    ports:
    - protocol: TCP
      port: 8080
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: database
    ports:
    - protocol: TCP
      port: 5432
```

### **Secret Management**

#### **Secret Naming and Structure**
```yaml
# Use External Secrets Operator for all secrets
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-secrets
  namespace: production
spec:
  refreshInterval: 15m
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: app-secrets
    creationPolicy: Owner
    template:
      type: Opaque
      metadata:
        labels:
          app.kubernetes.io/name: "user-service"
          environment: "production"
      data:
        database-url: "postgresql://{{ .username }}:{{ .password }}@{{ .host }}:{{ .port }}/{{ .database }}"
  data:
  - secretKey: username
    remoteRef:
      key: database/production
      property: username
```

#### **Certificate Management**
```yaml
# Use cert-manager for all TLS certificates
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: api-tls-cert
  namespace: production
spec:
  secretName: api-tls-cert
  issuerRef:
    name: letsencrypt-production
    kind: ClusterIssuer
  dnsNames:
  - api.example.com
  - api-v2.example.com
  usages:
  - digital signature
  - key encipherment
  duration: 2160h  # 90 days
  renewBefore: 360h  # 15 days before expiry
```

---

## 🏗️ **Infrastructure Standards**

### **Terraform Standards**

#### **Module Structure**
```hcl
# modules/<module-name>/main.tf
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

# Variable validation
variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.cluster_name))
    error_message = "Cluster name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Resource tagging
resource "aws_eks_cluster" "cluster" {
  name = var.cluster_name
  
  tags = merge(var.common_tags, {
    Name        = var.cluster_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Project     = var.project_name
  })
}
```

#### **State Management**
```hcl
# Use remote state for all environments
terraform {
  backend "s3" {
    bucket         = "terraform-state-bucket"
    key            = "kubernetes/production/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

### **Helm Chart Standards**

#### **Chart Structure**
```yaml
# Chart.yaml
apiVersion: v2
name: user-service
description: User management service
type: application
version: 1.0.0
appVersion: "v1.2.3"
maintainers:
- name: Platform Team
  email: platform-team@example.com

# values.yaml structure
image:
  repository: user-service
  tag: v1.2.3
  pullPolicy: IfNotPresent

replicaCount: 3

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70

service:
  type: ClusterIP
  port: 80
  targetPort: 8080

ingress:
  enabled: true
  className: istio
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-production
  hosts:
  - host: api.example.com
    paths:
    - path: /users
      pathType: Prefix
  tls:
  - secretName: api-tls-cert
    hosts:
    - api.example.com
```

---

## 📊 **Monitoring Standards**

### **Metrics and Alerting**

#### **SLI/SLO Definitions**
```yaml
# Service Level Indicators
slis:
  availability:
    description: "Percentage of successful requests"
    query: "sum(rate(http_requests_total{status!~'5..'}[5m])) / sum(rate(http_requests_total[5m]))"
    target: 99.9%
  
  latency:
    description: "95th percentile response time"
    query: "histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))"
    target: 100ms
  
  error_rate:
    description: "Percentage of error responses"
    query: "sum(rate(http_requests_total{status=~'5..'}[5m])) / sum(rate(http_requests_total[5m]))"
    target: 0.1%

# Service Level Objectives
slos:
  availability: 99.9%
  latency_p95: 100ms
  error_rate: 0.1%
```

#### **Alert Rules**
```yaml
groups:
- name: user-service.rules
  rules:
  - alert: HighErrorRate
    expr: sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m])) > 0.01
    for: 5m
    labels:
      severity: critical
      service: user-service
    annotations:
      summary: "High error rate detected"
      description: "Error rate is {{ $value | humanizePercentage }} for the last 5 minutes"
      runbook_url: "https://runbooks.example.com/high-error-rate"
```

### **Logging Standards**

#### **Log Format**
```json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "level": "INFO",
  "service": "user-service",
  "version": "v1.2.3",
  "trace_id": "abc123def456",
  "span_id": "789ghi012",
  "user_id": "user123",
  "request_id": "req-456",
  "method": "POST",
  "path": "/users",
  "status_code": 201,
  "duration_ms": 45,
  "message": "User created successfully",
  "environment": "production"
}
```

#### **Log Levels**
- **ERROR**: System errors, exceptions, failures
- **WARN**: Potential issues, deprecated features
- **INFO**: General application flow, business events
- **DEBUG**: Detailed diagnostic information (dev/staging only)

---

## 🚀 **Deployment Standards**

### **GitOps Workflow**

#### **Branch Strategy**
```
main                    # Production deployments
├── develop            # Integration branch
├── staging            # Staging deployments
└── feature/*          # Feature branches
```

#### **Environment Promotion**
```yaml
# Automatic promotion flow
dev → staging → production

# Approval gates
- dev: Automatic on merge to develop
- staging: Automatic on merge to staging
- production: Manual approval required
```

### **Container Image Standards**

#### **Image Tagging**
```bash
# Semantic versioning for releases
user-service:v1.2.3

# Environment-specific tags
user-service:staging-latest
user-service:production-v1.2.3

# Git-based tags for development
user-service:dev-abc123f
user-service:pr-456-def789
```

#### **Dockerfile Standards**
```dockerfile
# Use specific base image versions
FROM node:18.17-alpine3.18

# Create non-root user
RUN addgroup -g 1000 app && \
    adduser -u 1000 -G app -s /bin/sh -D app

# Set working directory
WORKDIR /app

# Copy package files first (layer caching)
COPY package*.json ./
RUN npm ci --only=production && npm cache clean --force

# Copy application code
COPY --chown=app:app . .

# Switch to non-root user
USER app

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

# Start application
CMD ["node", "server.js"]
```

---

## 🔧 **Configuration Management**

### **Environment-Specific Configuration**

#### **ConfigMap Structure**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: production
  labels:
    app.kubernetes.io/name: user-service
    environment: production
data:
  # Application configuration
  LOG_LEVEL: "info"
  PORT: "8080"
  NODE_ENV: "production"
  
  # Feature flags
  FEATURE_NEW_API: "true"
  FEATURE_BETA_UI: "false"
  
  # External service URLs
  DATABASE_HOST: "postgres.production.svc.cluster.local"
  REDIS_HOST: "redis.production.svc.cluster.local"
  
  # Performance tuning
  MAX_CONNECTIONS: "100"
  TIMEOUT_MS: "5000"
  RETRY_ATTEMPTS: "3"
```

### **Resource Quotas**

#### **Namespace Resource Limits**
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: production-quota
  namespace: production
spec:
  hard:
    # Compute resources
    requests.cpu: "20"
    requests.memory: "40Gi"
    limits.cpu: "40"
    limits.memory: "80Gi"
    
    # Storage resources
    persistentvolumeclaims: "20"
    requests.storage: "1Ti"
    
    # Object counts
    pods: "50"
    services: "20"
    secrets: "30"
    configmaps: "30"
    
    # Load balancers
    services.loadbalancers: "5"
```

---

## 📈 **Performance Standards**

### **Resource Allocation**

#### **Application Tiers**
```yaml
# Frontend applications
resources:
  requests:
    cpu: "50m"
    memory: "64Mi"
  limits:
    cpu: "200m"
    memory: "256Mi"

# Backend services
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "512Mi"

# Database workloads
resources:
  requests:
    cpu: "500m"
    memory: "1Gi"
  limits:
    cpu: "2000m"
    memory: "4Gi"
```

### **Scaling Policies**

#### **Horizontal Pod Autoscaler**
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: user-service-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: user-service
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
      - type: Percent
        value: 100
        periodSeconds: 15
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 10
        periodSeconds: 60
```

---

## 🧪 **Testing Standards**

### **Health Checks**

#### **Kubernetes Probes**
```yaml
spec:
  containers:
  - name: app
    livenessProbe:
      httpGet:
        path: /health
        port: 8080
      initialDelaySeconds: 30
      periodSeconds: 10
      timeoutSeconds: 5
      failureThreshold: 3
    
    readinessProbe:
      httpGet:
        path: /ready
        port: 8080
      initialDelaySeconds: 5
      periodSeconds: 5
      timeoutSeconds: 3
      failureThreshold: 3
    
    startupProbe:
      httpGet:
        path: /health
        port: 8080
      initialDelaySeconds: 10
      periodSeconds: 10
      timeoutSeconds: 5
      failureThreshold: 30
```

### **Load Testing**

#### **Performance Benchmarks**
```yaml
# Minimum performance requirements
performance_targets:
  rps: 1000              # Requests per second
  latency_p95: 100ms     # 95th percentile latency
  latency_p99: 500ms     # 99th percentile latency
  error_rate: 0.1%       # Maximum error rate
  availability: 99.9%    # Uptime requirement
```

---

## 📚 **Documentation Standards**

### **Code Documentation**

#### **README Structure**
```markdown
# Service Name

Brief description of the service purpose and functionality.

## Quick Start
- Prerequisites
- Installation steps
- Basic usage examples

## Architecture
- System overview
- Dependencies
- Data flow

## Configuration
- Environment variables
- Configuration files
- Feature flags

## API Documentation
- Endpoints
- Request/response examples
- Authentication

## Deployment
- Build process
- Deployment steps
- Environment-specific notes

## Monitoring
- Health checks
- Metrics
- Alerts

## Troubleshooting
- Common issues
- Debug procedures
- Contact information
```

### **Runbook Standards**

#### **Incident Response**
```markdown
# Service Incident Runbook

## Alert: High Error Rate

### Symptoms
- Error rate > 1%
- Increased response times
- User complaints

### Investigation Steps
1. Check service logs: `kubectl logs -l app=user-service`
2. Verify database connectivity
3. Check resource utilization
4. Review recent deployments

### Mitigation Steps
1. Scale up replicas if CPU/memory high
2. Restart pods if memory leaks detected
3. Rollback if recent deployment caused issue
4. Enable circuit breaker if downstream issues

### Escalation
- Primary: platform-team@example.com
- Secondary: engineering-lead@example.com
- Emergency: +1-555-0123
```

---

These standards ensure consistency, security, and maintainability across the entire platform. All team members should follow these guidelines when contributing to the infrastructure and applications.

