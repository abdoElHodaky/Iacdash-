# 🔄 GitOps with FluxCD

Complete guide for implementing GitOps workflows with FluxCD and progressive delivery with Flagger.

---

## 📋 Table of Contents

- [Overview](#overview)
- [FluxCD Installation](#fluxcd-installation)
- [Repository Structure](#repository-structure)
- [GitOps Resources](#gitops-resources)
- [Helm Releases](#helm-releases)
- [Kustomizations](#kustomizations)
- [Progressive Delivery](#progressive-delivery)
- [Multi-Environment Management](#multi-environment-management)
- [Image Automation](#image-automation)
- [Secrets Management](#secrets-management)
- [Best Practices](#best-practices)

---

## Overview

GitOps provides:

- **Declarative Infrastructure**: Everything defined in Git
- **Automated Deployments**: Continuous reconciliation
- **Audit Trail**: Git history as change log
- **Rollback Capability**: Git revert = infrastructure rollback
- **Progressive Delivery**: Automated canary deployments

### FluxCD Architecture

```
┌─────────────────────────────────────────────┐
│              Git Repository                  │
│  • Infrastructure definitions                │
│  • Application manifests                     │
│  • Helm charts                               │
└──────────────┬──────────────────────────────┘
               │ Git sync
┌──────────────▼──────────────────────────────┐
│          FluxCD Controllers                  │
│  ┌────────────┐  ┌────────────┐            │
│  │  Source    │  │   Helm     │            │
│  │ Controller │  │ Controller │            │
│  └────────────┘  └────────────┘            │
│  ┌────────────┐  ┌────────────┐            │
│  │ Kustomize  │  │   Image    │            │
│  │ Controller │  │ Automation │            │
│  └────────────┘  └────────────┘            │
└──────────────┬──────────────────────────────┘
               │ Apply to cluster
┌──────────────▼──────────────────────────────┐
│         Kubernetes Cluster                   │
│  • Gateway API                               │
│  • Service Mesh                              │
│  • Applications                              │
└──────────────────────────────────────────────┘
```

---

## FluxCD Installation

### Prerequisites

```bash
# Install Flux CLI
curl -s https://fluxcd.io/install.sh | sudo bash

# Or with Homebrew
brew install fluxcd/tap/flux

# Verify installation
flux --version

# Set GitHub credentials
export GITHUB_TOKEN="ghp_xxxxxxxxxxxxx"
export GITHUB_USER="your-username"
```

### Pre-flight Check

```bash
# Check cluster prerequisites
flux check --pre

# Expected output:
# ✔ Kubernetes 1.28.0 >=1.26.0-0
# ✔ prerequisites checks passed
```

### Bootstrap FluxCD

```bash
# Bootstrap to GitHub
flux bootstrap github \
  --owner=$GITHUB_USER \
  --repository=infrastructure-config \
  --branch=main \
  --path=clusters/production \
  --personal \
  --token-auth

# Or for GitLab
flux bootstrap gitlab \
  --owner=$GITLAB_USER \
  --repository=infrastructure-config \
  --branch=main \
  --path=clusters/production \
  --token-auth

# Verify installation
flux check
kubectl get pods -n flux-system
```

### What Bootstrap Creates

```
infrastructure-config/
├── clusters/
│   └── production/
│       └── flux-system/
│           ├── gotk-components.yaml     # FluxCD controllers
│           ├── gotk-sync.yaml           # GitRepository + Kustomization
│           └── kustomization.yaml       # Kustomize config
```

---

## Repository Structure

### Recommended Layout

```
infrastructure-config/
├── clusters/                      # Cluster-specific configs
│   ├── dev/
│   │   ├── flux-system/
│   │   ├── infrastructure.yaml
│   │   └── apps.yaml
│   ├── staging/
│   │   ├── flux-system/
│   │   ├── infrastructure.yaml
│   │   └── apps.yaml
│   └── production/
│       ├── flux-system/
│       ├── infrastructure.yaml
│       └── apps.yaml
├── infrastructure/                # Infrastructure components
│   ├── gateway-api/
│   │   ├── gatewayclass.yaml
│   │   ├── gateway.yaml
│   │   └── kustomization.yaml
│   ├── service-mesh/
│   │   ├── istio/
│   │   │   ├── helmrelease.yaml
│   │   │   └── kustomization.yaml
│   │   └── kustomization.yaml
│   ├── monitoring/
│   │   ├── prometheus/
│   │   ├── grafana/
│   │   └── kustomization.yaml
│   └── transformations/
│       ├── envoy-filters/
│       ├── opa-policies/
│       └── kustomization.yaml
├── apps/                          # Application definitions
│   ├── base/
│   │   ├── api-service/
│   │   │   ├── deployment.yaml
│   │   │   ├── service.yaml
│   │   │   ├── httproute.yaml
│   │   │   └── kustomization.yaml
│   │   └── web-app/
│   └── overlays/
│       ├── dev/
│       ├── staging/
│       └── production/
└── tenants/                       # Multi-tenant configs
    ├── tenant-a/
    └── tenant-b/
```

---

## GitOps Resources

### GitRepository Source

```yaml
# clusters/production/sources.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: infrastructure-config
  namespace: flux-system
spec:
  interval: 1m
  url: https://github.com/your-org/infrastructure-config
  ref:
    branch: main
  secretRef:
    name: github-token
  ignore: |
    # Exclude files
    /**/README.md
    /**/test/
```

### HelmRepository Source

```yaml
# clusters/production/helm-sources.yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: prometheus-community
  namespace: flux-system
spec:
  interval: 10m
  url: https://prometheus-community.github.io/helm-charts
---
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: grafana
  namespace: flux-system
spec:
  interval: 10m
  url: https://grafana.github.io/helm-charts
---
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: istio
  namespace: flux-system
spec:
  interval: 10m
  url: https://istio-release.storage.googleapis.com/charts
```

---

## Helm Releases

### Istio HelmRelease

```yaml
# infrastructure/service-mesh/istio/helmrelease.yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: istio-base
  namespace: istio-system
spec:
  interval: 10m
  chart:
    spec:
      chart: base
      version: 1.20.x
      sourceRef:
        kind: HelmRepository
        name: istio
        namespace: flux-system
  install:
    crds: Create
  upgrade:
    crds: CreateReplace
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: istiod
  namespace: istio-system
spec:
  interval: 10m
  dependsOn:
  - name: istio-base
  chart:
    spec:
      chart: istiod
      version: 1.20.x
      sourceRef:
        kind: HelmRepository
        name: istio
        namespace: flux-system
  values:
    pilot:
      resources:
        requests:
          cpu: 500m
          memory: 2048Mi
    meshConfig:
      accessLogFile: /dev/stdout
    global:
      proxy:
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
```

### Prometheus Stack HelmRelease

```yaml
# infrastructure/monitoring/prometheus/helmrelease.yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: kube-prometheus-stack
  namespace: monitoring
spec:
  interval: 10m
  timeout: 15m
  chart:
    spec:
      chart: kube-prometheus-stack
      version: 55.x
      sourceRef:
        kind: HelmRepository
        name: prometheus-community
        namespace: flux-system
  
  # Reconcile on Git changes
  interval: 5m
  
  # Automatic upgrades
  upgrade:
    remediation:
      retries: 3
  
  # Custom values
  values:
    prometheus:
      prometheusSpec:
        retention: 30d
        storageSpec:
          volumeClaimTemplate:
            spec:
              accessModes: ["ReadWriteOnce"]
              resources:
                requests:
                  storage: 50Gi
        
        # Service monitors
        serviceMonitorSelectorNilUsesHelmValues: false
        
        # External labels
        externalLabels:
          cluster: production
          environment: prod
    
    grafana:
      adminPassword: ${GRAFANA_ADMIN_PASSWORD}
      persistence:
        enabled: true
        size: 10Gi
      
      # Datasources
      additionalDataSources:
      - name: Loki
        type: loki
        url: http://loki.monitoring:3100
      - name: Tempo
        type: tempo
        url: http://tempo.monitoring:3100
      
      # Dashboards
      dashboardProviders:
        dashboardproviders.yaml:
          apiVersion: 1
          providers:
          - name: 'default'
            folder: 'General'
            type: file
            options:
              path: /var/lib/grafana/dashboards/default
      
      dashboards:
        default:
          gateway-performance:
            gnetId: 15474
            revision: 1
            datasource: Prometheus
    
    alertmanager:
      config:
        global:
          resolve_timeout: 5m
        route:
          group_by: ['alertname', 'cluster']
          group_wait: 10s
          group_interval: 10s
          repeat_interval: 12h
          receiver: 'slack'
        receivers:
        - name: 'slack'
          slack_configs:
          - api_url: ${SLACK_WEBHOOK_URL}
            channel: '#alerts'
            title: '{{ .GroupLabels.alertname }}'
            text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
```

### Post-Installation Health Check

```yaml
# infrastructure/monitoring/prometheus/helmrelease.yaml (continued)
spec:
  # ... previous config
  
  # Health checks
  test:
    enable: true
  
  # Post-install hooks
  postRenderers:
  - kustomize:
      patches:
      - target:
          kind: Service
          name: kube-prometheus-stack-prometheus
        patch: |
          - op: add
            path: /metadata/annotations
            value:
              external-dns.alpha.kubernetes.io/hostname: prometheus.example.com
```

---

## Kustomizations

### Infrastructure Kustomization

```yaml
# clusters/production/infrastructure.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure
  namespace: flux-system
spec:
  interval: 10m
  retryInterval: 1m
  timeout: 5m
  
  sourceRef:
    kind: GitRepository
    name: infrastructure-config
  
  path: ./infrastructure
  
  prune: true
  wait: true
  
  # Health checks
  healthChecks:
  - apiVersion: apps/v1
    kind: Deployment
    name: istiod
    namespace: istio-system
  
  # Dependencies (deploy in order)
  dependsOn:
  - name: flux-system
```

### Application Kustomization

```yaml
# clusters/production/apps.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  interval: 5m
  retryInterval: 1m
  
  sourceRef:
    kind: GitRepository
    name: infrastructure-config
  
  path: ./apps/overlays/production
  
  prune: true
  wait: true
  
  # Substitute variables
  postBuild:
    substitute:
      ENVIRONMENT: "production"
      REGION: "us-east-1"
      REPLICAS: "3"
    substituteFrom:
    - kind: ConfigMap
      name: cluster-config
  
  # Depend on infrastructure
  dependsOn:
  - name: infrastructure
```

### Tenant Kustomization (Multi-Tenancy)

```yaml
# clusters/production/tenants.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: tenant-a
  namespace: flux-system
spec:
  interval: 10m
  
  sourceRef:
    kind: GitRepository
    name: infrastructure-config
  
  path: ./tenants/tenant-a
  
  targetNamespace: tenant-a
  
  # Service account for tenant
  serviceAccountName: tenant-a-reconciler
  
  prune: true
  
  # Patches for tenant customization
  patches:
  - target:
      kind: Deployment
    patch: |
      - op: add
        path: /spec/template/spec/containers/0/env/-
        value:
          name: TENANT_ID
          value: tenant-a
```

---

## Progressive Delivery

### Install Flagger

```bash
# Add Flagger to flux-system
flux install \
  --components-extra=image-reflector-controller,image-automation-controller

# Install Flagger
kubectl apply -k github.com/fluxcd/flagger//kustomize/istio

# Or with Helm
flux create source helm flagger \
  --url=https://flagger.app \
  --namespace=flux-system

flux create helmrelease flagger \
  --source=HelmRepository/flagger \
  --chart=flagger \
  --namespace=istio-system \
  --values=- <<EOF
meshProvider: istio
metricsServer: http://prometheus.monitoring:9090
EOF
```

### Canary Deployment

```yaml
# apps/base/api-service/canary.yaml
apiVersion: flagger.app/v1beta1
kind: Canary
metadata:
  name: api-service
  namespace: default
spec:
  # Deployment reference
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api-service
  
  # Service reference
  service:
    port: 8080
    targetPort: 8080
    
    # Gateway API integration
    gatewayRefs:
    - name: production-gateway
      namespace: default
  
  # Progressive rollout strategy
  analysis:
    interval: 1m
    threshold: 5
    maxWeight: 50
    stepWeight: 10
    
    # Metrics for canary analysis
    metrics:
    - name: request-success-rate
      thresholdRange:
        min: 99
      interval: 1m
    
    - name: request-duration
      thresholdRange:
        max: 500
      interval: 1m
    
    - name: error-rate
      thresholdRange:
        max: 1
      interval: 1m
    
    # Webhooks for testing
    webhooks:
    - name: load-test
      url: http://flagger-loadtester.test/
      timeout: 5s
      metadata:
        type: cmd
        cmd: "hey -z 1m -q 10 -c 2 http://api-service-canary.default:8080/"
    
    - name: smoke-test
      url: http://flagger-loadtester.test/
      timeout: 5s
      metadata:
        type: bash
        cmd: |
          curl -s http://api-service-canary.default:8080/health | \
          grep -q "ok" && exit 0 || exit 1
```

### Canary Phases

```
Initial → 0% canary traffic
  ↓
Start → 10% canary traffic (validate)
  ↓
Progress → 20%, 30%, 40%, 50% (step by 10%)
  ↓
Success → 100% canary (promote)
  OR
Failure → 0% canary (rollback)
```

### Blue-Green Deployment

```yaml
# apps/base/web-app/canary.yaml
apiVersion: flagger.app/v1beta1
kind: Canary
metadata:
  name: web-app
  namespace: default
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web-app
  
  service:
    port: 80
  
  # Blue-green strategy
  analysis:
    interval: 1m
    threshold: 10
    iterations: 10
    
    # Switch all traffic at once
    stepWeight: 100
    maxWeight: 100
    
    metrics:
    - name: request-success-rate
      thresholdRange:
        min: 99
      interval: 1m
```

### A/B Testing

```yaml
# apps/base/frontend/canary.yaml
apiVersion: flagger.app/v1beta1
kind: Canary
metadata:
  name: frontend
  namespace: default
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: frontend
  
  service:
    port: 80
  
  # A/B testing with header matching
  analysis:
    interval: 1m
    threshold: 10
    iterations: 10
    
    # Match specific header
    match:
    - headers:
        x-canary:
          exact: "beta"
    
    metrics:
    - name: request-success-rate
      thresholdRange:
        min: 99
      interval: 1m
```

---

## Multi-Environment Management

### Environment-Specific Overlays

```yaml
# apps/overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: default

resources:
- ../../base/api-service

patches:
# Reduce replicas for dev
- target:
    kind: Deployment
    name: api-service
  patch: |
    - op: replace
      path: /spec/replicas
      value: 1

# Use dev image tag
- target:
    kind: Deployment
    name: api-service
  patch: |
    - op: replace
      path: /spec/template/spec/containers/0/image
      value: ghcr.io/org/api-service:dev

# Add dev environment variables
- target:
    kind: Deployment
    name: api-service
  patch: |
    - op: add
      path: /spec/template/spec/containers/0/env/-
      value:
        name: ENVIRONMENT
        value: development
```

```yaml
# apps/overlays/production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: default

resources:
- ../../base/api-service

patches:
# Scale for production
- target:
    kind: Deployment
    name: api-service
  patch: |
    - op: replace
      path: /spec/replicas
      value: 5

# Use stable image tag
- target:
    kind: Deployment
    name: api-service
  patch: |
    - op: replace
      path: /spec/template/spec/containers/0/image
      value: ghcr.io/org/api-service:v1.2.3

# Add production resources
- target:
    kind: Deployment
    name: api-service
  patch: |
    - op: add
      path: /spec/template/spec/containers/0/resources
      value:
        requests:
          cpu: 500m
          memory: 512Mi
        limits:
          cpu: 2000m
          memory: 2048Mi
```

---

## Image Automation

### ImageRepository

```yaml
# clusters/production/image-automation.yaml
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: api-service
  namespace: flux-system
spec:
  image: ghcr.io/your-org/api-service
  interval: 5m
  secretRef:
    name: github-registry-creds
```

### ImagePolicy

```yaml
# clusters/production/image-automation.yaml
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: api-service-prod
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: api-service
  
  # Semantic versioning
  policy:
    semver:
      range: 1.x.x
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: api-service-dev
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: api-service
  
  # Latest dev tag
  policy:
    alphabetical:
      order: asc
  filterTags:
    pattern: '^dev-[a-f0-9]+-(?P<ts>[0-9]+)$'
    extract: '$ts'
```

### ImageUpdateAutomation

```yaml
# clusters/production/image-automation.yaml
apiVersion: image.toolkit.fluxcd.io/v1beta1
kind: ImageUpdateAutomation
metadata:
  name: api-service-automation
  namespace: flux-system
spec:
  interval: 5m
  
  sourceRef:
    kind: GitRepository
    name: infrastructure-config
  
  git:
    checkout:
      ref:
        branch: main
    commit:
      author:
        email: fluxcd@example.com
        name: FluxCD
      messageTemplate: |
        Automated image update
        
        [ci skip]
    push:
      branch: main
  
  update:
    path: ./apps/overlays/production
    strategy: Setters
```

### Mark Images for Automation

```yaml
# apps/base/api-service/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-service
spec:
  replicas: 3
  selector:
    matchLabels:
      app: api-service
  template:
    metadata:
      labels:
        app: api-service
    spec:
      containers:
      - name: api-service
        image: ghcr.io/your-org/api-service:v1.0.0  # {"$imagepolicy": "flux-system:api-service-prod"}
        ports:
        - containerPort: 8080
```

---

## Secrets Management

### Sealed Secrets

```bash
# Install Sealed Secrets controller
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

# Install kubeseal CLI
brew install kubeseal

# Create sealed secret
kubectl create secret generic api-credentials \
  --from-literal=api-key=secret123 \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > sealed-secret.yaml

# Commit sealed secret to Git (safe!)
git add sealed-secret.yaml
git commit -m "Add API credentials"
git push
```

### SOPS (Mozilla)

```bash
# Install SOPS
brew install sops

# Create encryption key (Age)
age-keygen -o age.key

# Encrypt secret
sops --age $(cat age.key | grep public | cut -d: -f2) \
  --encrypt secret.yaml > secret.enc.yaml

# Configure Flux to decrypt
flux create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=age.key

# Reference in Kustomization
spec:
  decryption:
    provider: sops
    secretRef:
      name: sops-age
```

### External Secrets Operator

```yaml
# infrastructure/secrets/external-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: default
spec:
  provider:
    vault:
      server: "https://vault.example.com"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "app-role"
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: api-credentials
  namespace: default
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: api-credentials
    creationPolicy: Owner
  data:
  - secretKey: api-key
    remoteRef:
      key: api-service
      property: key
```

---

## Best Practices

### 1. Repository Organization

✅ **DO:**
- Separate infrastructure and applications
- Use overlays for environment differences
- Keep secrets encrypted
- Document dependencies

❌ **DON'T:**
- Mix environments in same path
- Commit plain secrets
- Create circular dependencies

### 2. Reconciliation

✅ **DO:**
- Set appropriate intervals (5-10m)
- Use health checks
- Configure retries
- Monitor reconciliation status

❌ **DON'T:**
- Use very short intervals (< 1m)
- Skip dependency management
- Ignore failed reconciliations

### 3. Progressive Delivery

✅ **DO:**
- Start with small canary percentages
- Define clear success metrics
- Implement automated rollback
- Test in staging first

❌ **DON'T:**
- Skip metrics validation
- Deploy 50/50 immediately
- Ignore webhook tests

### 4. Security

✅ **DO:**
- Encrypt all secrets
- Use RBAC for tenants
- Rotate credentials regularly
- Audit Git access

❌ **DON'T:**
- Commit plain secrets
- Share encryption keys
- Skip access reviews

---

## Monitoring GitOps

### Check Status

```bash
# View all Flux resources
flux get all -A

# Check specific resource
flux get kustomizations
flux get helmreleases -A
flux get sources git -A

# View events
flux events --for Kustomization/infrastructure

# Logs
flux logs --level=error
```

### Reconcile Manually

```bash
# Force reconciliation
flux reconcile source git infrastructure-config
flux reconcile kustomization infrastructure --with-source

# Suspend/resume
flux suspend kustomization apps
flux resume kustomization apps
```

### Troubleshooting

```bash
# Check why reconciliation failed
kubectl describe kustomization infrastructure -n flux-system

# View controller logs
kubectl logs -n flux-system deploy/source-controller
kubectl logs -n flux-system deploy/kustomize-controller

# Validate resources locally
flux build kustomization infrastructure \
  --path ./infrastructure \
  --kustomization-file ./clusters/production/infrastructure.yaml
```

---

**Next Steps:**
- Setup monitoring: [MONITORING.md](MONITORING.md)
- Implement security: [SECURITY.md](SECURITY.md)
- Troubleshooting guide: [TROUBLESHOOTING.md](TROUBLESHOOTING.md)