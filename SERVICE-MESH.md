# 🕸️ Service Mesh Configuration Guide

Complete guide for implementing Istio or Linkerd service mesh with mTLS, traffic management, and observability.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Choosing a Service Mesh](#choosing-a-service-mesh)
- [Istio Installation](#istio-installation)
- [Linkerd Installation](#linkerd-installation)
- [mTLS Configuration](#mtls-configuration)
- [Traffic Management](#traffic-management)
- [Resilience Patterns](#resilience-patterns)
- [Security Policies](#security-policies)
- [Multi-Cluster Mesh](#multi-cluster-mesh)
- [Observability](#observability)
- [Best Practices](#best-practices)

---

## Overview

A service mesh provides:

- **Security**: Automatic mTLS encryption between services
- **Observability**: Metrics, logs, and distributed tracing
- **Traffic Management**: Load balancing, retries, circuit breaking
- **Resilience**: Fault injection, timeouts, rate limiting
- **Policy Enforcement**: Authorization, access control

### Architecture

```
┌─────────────────────────────────────────────┐
│         Control Plane (istiod/linkerd)      │
│  • Certificate Authority                     │
│  • Configuration Management                  │
│  • Service Discovery                         │
└──────────────┬──────────────────────────────┘
               │
    ┌──────────┴──────────┐
    │                     │
┌───▼────┐           ┌───▼────┐
│ Pod A  │           │ Pod B  │
│┌──────┐│  mTLS    │┌──────┐│
││ App  ││◄─────────►││ App  ││
│└──────┘│           │└──────┘│
│┌──────┐│           │┌──────┐│
││Proxy ││           ││Proxy ││
│└──────┘│           │└──────┘│
└────────┘           └────────┘
  Sidecar              Sidecar
```

---

## Choosing a Service Mesh

| Feature | Istio | Linkerd |
|---------|-------|---------|
| **Complexity** | High | Low |
| **Features** | Comprehensive | Essential |
| **Performance** | Good | Excellent |
| **Resource Usage** | Higher | Lower |
| **Learning Curve** | Steep | Gentle |
| **Best For** | Enterprise, feature-rich | Simplicity, performance |

### When to Choose Istio

✅ Need advanced traffic management  
✅ Multi-cluster deployments  
✅ Complex authorization policies  
✅ Gateway API integration  
✅ Enterprise support required  

### When to Choose Linkerd

✅ Prioritize simplicity  
✅ Lower resource overhead  
✅ Fast time-to-value  
✅ Kubernetes-native approach  
✅ Excellent observability out-of-box  

---

## Istio Installation

### Prerequisites

```bash
# Install Istio CLI
curl -L https://istio.io/downloadIstio | sh -
cd istio-*/
export PATH=$PWD/bin:$PATH

# Verify installation
istioctl version
```

### Installation Profiles

```bash
# Demo profile (development)
istioctl install --set profile=demo -y

# Production profile (recommended)
istioctl install --set profile=production -y

# Minimal profile (lightweight)
istioctl install --set profile=minimal -y

# Custom profile
istioctl install --set profile=default \
  --set values.pilot.resources.requests.cpu=500m \
  --set values.pilot.resources.requests.memory=2048Mi \
  --set meshConfig.accessLogFile=/dev/stdout
```

### Production Installation

```yaml
# istio/istio-operator.yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  name: production-install
  namespace: istio-system
spec:
  profile: production
  
  # Hub and tag
  hub: docker.io/istio
  tag: 1.20.1
  
  # Mesh configuration
  meshConfig:
    # Enable access logs
    accessLogFile: /dev/stdout
    accessLogFormat: |
      [%START_TIME%] "%REQ(:METHOD)% %REQ(X-ENVOY-ORIGINAL-PATH?:PATH)% %PROTOCOL%" %RESPONSE_CODE% %RESPONSE_FLAGS% %BYTES_RECEIVED% %BYTES_SENT% %DURATION% %RESP(X-ENVOY-UPSTREAM-SERVICE-TIME)% "%REQ(X-FORWARDED-FOR)%" "%REQ(USER-AGENT)%" "%REQ(X-REQUEST-ID)%" "%REQ(:AUTHORITY)%" "%UPSTREAM_HOST%"
    
    # Default mTLS mode
    defaultConfig:
      proxyMetadata:
        ISTIO_META_DNS_CAPTURE: "true"
        ISTIO_META_DNS_AUTO_ALLOCATE: "true"
    
    # Enable tracing
    enableTracing: true
    defaultConfig:
      tracing:
        zipkin:
          address: zipkin.istio-system:9411
        sampling: 100.0
    
    # Trust domain
    trustDomain: cluster.local
  
  # Component configuration
  components:
    # Ingress gateway
    ingressGateways:
    - name: istio-ingressgateway
      enabled: true
      k8s:
        replicas: 3
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
          limits:
            cpu: 2000m
            memory: 2048Mi
        hpaSpec:
          minReplicas: 3
          maxReplicas: 10
          metrics:
          - type: Resource
            resource:
              name: cpu
              targetAverageUtilization: 80
        service:
          type: LoadBalancer
          ports:
          - name: http2
            port: 80
            targetPort: 8080
          - name: https
            port: 443
            targetPort: 8443
    
    # Egress gateway
    egressGateways:
    - name: istio-egressgateway
      enabled: true
      k8s:
        replicas: 2
    
    # Pilot (istiod)
    pilot:
      k8s:
        replicas: 2
        resources:
          requests:
            cpu: 500m
            memory: 2048Mi
          limits:
            cpu: 2000m
            memory: 4096Mi
        hpaSpec:
          minReplicas: 2
          maxReplicas: 5
  
  # Values overrides
  values:
    global:
      # Logging level
      logging:
        level: "default:info"
      
      # Proxy configuration
      proxy:
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 2000m
            memory: 1024Mi
        
        # Access log format
        accessLogFormat: |
          [%START_TIME%] "%REQ(:METHOD)% %REQ(X-ENVOY-ORIGINAL-PATH?:PATH)%"
```

### Apply Installation

```bash
# Install with operator
kubectl create namespace istio-system
kubectl apply -f istio/istio-operator.yaml

# Or use istioctl
istioctl install -f istio/istio-operator.yaml -y

# Verify installation
kubectl get pods -n istio-system
istioctl verify-install

# Check version
istioctl version
```

### Enable Sidecar Injection

```bash
# Label namespace for automatic injection
kubectl label namespace default istio-injection=enabled

# Verify label
kubectl get namespace -L istio-injection

# Manually inject (without automatic injection)
istioctl kube-inject -f deployment.yaml | kubectl apply -f -

# Verify injection
kubectl get pods -o jsonpath='{.items[*].spec.containers[*].name}'
# Should show both app and istio-proxy containers
```

---

## Linkerd Installation

### Prerequisites

```bash
# Install Linkerd CLI
curl -sL https://run.linkerd.io/install | sh
export PATH=$HOME/.linkerd2/bin:$PATH

# Verify CLI
linkerd version
```

### Pre-flight Check

```bash
# Verify cluster is ready
linkerd check --pre

# Should show all checks passing
```

### Installation

```bash
# Install CRDs
linkerd install --crds | kubectl apply -f -

# Install control plane
linkerd install | kubectl apply -f -

# Verify installation
linkerd check

# View dashboard
linkerd viz install | kubectl apply -f -
linkerd viz dashboard
```

### Production Installation

```yaml
# linkerd/linkerd-values.yaml
# Generate with: linkerd install --values linkerd-values.yaml

controllerReplicas: 3
destinationReplicas: 3
identityReplicas: 3

# High availability
enablePodAntiAffinity: true

# Resource limits
proxy:
  resources:
    cpu:
      request: 100m
      limit: 1000m
    memory:
      request: 128Mi
      limit: 512Mi

# Enable pod disruption budgets
enablePodDisruptionBudget: true

# Trust domain
identityTrustDomain: cluster.local

# Certificate duration
identity:
  issuer:
    issuanceLifetime: 24h0m0s
    clockSkewAllowance: 20s
```

### Enable Mesh for Namespaces

```bash
# Annotate namespace for injection
kubectl annotate namespace default linkerd.io/inject=enabled

# Verify
kubectl get namespace default -o yaml

# Rollout restart to inject proxies
kubectl rollout restart deployment -n default

# Check proxy status
linkerd check --proxy -n default
```

---

## mTLS Configuration

### Istio mTLS

#### PERMISSIVE Mode (gradual adoption)

```yaml
# service-mesh/istio/mtls-permissive.yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default-permissive
  namespace: istio-system
spec:
  mtls:
    mode: PERMISSIVE  # Accept both mTLS and plaintext
```

#### STRICT Mode (production)

```yaml
# service-mesh/istio/mtls-strict.yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default-strict
  namespace: istio-system
spec:
  mtls:
    mode: STRICT  # Only accept mTLS
---
# Override for specific namespace
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: namespace-mtls
  namespace: production
spec:
  mtls:
    mode: STRICT
```

#### Per-Service mTLS

```yaml
# service-mesh/istio/service-mtls.yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: api-service-mtls
  namespace: default
spec:
  selector:
    matchLabels:
      app: api-service
  mtls:
    mode: STRICT
  portLevelMtls:
    8080:
      mode: STRICT
    9090:
      mode: PERMISSIVE  # Metrics endpoint
```

#### Verify mTLS

```bash
# Check mTLS status
istioctl authn tls-check pod-name.namespace

# View certificates
istioctl proxy-config secret pod-name.namespace

# Test mTLS connection
kubectl exec -it pod-name -c istio-proxy -- \
  curl -v https://service-name.namespace.svc.cluster.local:8080
```

### Linkerd mTLS

Linkerd enables mTLS automatically for all meshed pods.

```bash
# Check mTLS status
linkerd viz tap deployment/api-service

# View certificate details
linkerd identity check

# Verify connections are secured
linkerd viz stat deployment --to deployment/backend-service
# Look for "SECURED" column
```

---

## Traffic Management

### Traffic Splitting (Canary)

#### Istio VirtualService

```yaml
# service-mesh/istio/canary-split.yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api-canary
  namespace: default
spec:
  hosts:
  - api-service
  
  http:
  # Canary for beta users
  - match:
    - headers:
        x-user-group:
          exact: beta
    route:
    - destination:
        host: api-service
        subset: v2
      weight: 100
  
  # Progressive rollout: 90% v1, 10% v2
  - route:
    - destination:
        host: api-service
        subset: v1
      weight: 90
    - destination:
        host: api-service
        subset: v2
      weight: 10
    
    # Add delay for testing
    fault:
      delay:
        percentage:
          value: 0.1
        fixedDelay: 5s
    
    # Retry configuration
    retries:
      attempts: 3
      perTryTimeout: 2s
      retryOn: 5xx,reset,connect-failure

---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: api-service-dr
  namespace: default
spec:
  host: api-service
  
  trafficPolicy:
    loadBalancer:
      consistentHash:
        httpHeaderName: x-user-id
    
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        http1MaxPendingRequests: 50
        http2MaxRequests: 100
    
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 30s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
  
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
```

#### Linkerd TrafficSplit

```yaml
# service-mesh/linkerd/traffic-split.yaml
apiVersion: split.smi-spec.io/v1alpha2
kind: TrafficSplit
metadata:
  name: api-canary
  namespace: default
spec:
  service: api-service
  
  backends:
  - service: api-service-v1
    weight: 90
  - service: api-service-v2
    weight: 10
```

### Request Routing

#### Header-Based Routing (Istio)

```yaml
# service-mesh/istio/header-routing.yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: header-based-routing
spec:
  hosts:
  - api-service
  
  http:
  # Route API v2 requests
  - match:
    - headers:
        api-version:
          exact: "v2"
    route:
    - destination:
        host: api-service
        subset: v2
  
  # Route mobile clients
  - match:
    - headers:
        user-agent:
          regex: ".*Mobile.*"
    route:
    - destination:
        host: mobile-backend
  
  # Default route
  - route:
    - destination:
        host: api-service
        subset: v1
```

### Request Timeouts

```yaml
# service-mesh/istio/timeouts.yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api-timeouts
spec:
  hosts:
  - api-service
  
  http:
  - route:
    - destination:
        host: api-service
    
    # Request timeout
    timeout: 10s
    
    # Retry policy
    retries:
      attempts: 3
      perTryTimeout: 3s
      retryOn: 5xx,reset,connect-failure,refused-stream
```

### Traffic Mirroring

```yaml
# service-mesh/istio/traffic-mirror.yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: mirror-traffic
spec:
  hosts:
  - api-service
  
  http:
  - route:
    - destination:
        host: api-service-production
      weight: 100
    
    # Mirror to test environment (no response to client)
    mirror:
      host: api-service-test
    mirrorPercentage:
      value: 10.0  # Mirror 10% of traffic
```

---

## Resilience Patterns

### Circuit Breaking

```yaml
# service-mesh/istio/circuit-breaker.yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: circuit-breaker
  namespace: default
spec:
  host: backend-service
  
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 1
      http:
        http1MaxPendingRequests: 1
        maxRequestsPerConnection: 1
    
    outlierDetection:
      consecutiveErrors: 1
      interval: 1s
      baseEjectionTime: 3m
      maxEjectionPercent: 100
      minHealthPercent: 50
```

### Fault Injection

```yaml
# service-mesh/istio/fault-injection.yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: fault-injection-test
spec:
  hosts:
  - api-service
  
  http:
  - match:
    - headers:
        x-test-fault:
          exact: "true"
    
    fault:
      # Inject delay
      delay:
        percentage:
          value: 100.0
        fixedDelay: 5s
      
      # Inject error
      abort:
        percentage:
          value: 10.0
        httpStatus: 500
    
    route:
    - destination:
        host: api-service
```

### Rate Limiting

```yaml
# service-mesh/istio/rate-limit.yaml
apiVersion: networking.istio.io/v1beta1
kind: EnvoyFilter
metadata:
  name: rate-limit-filter
  namespace: istio-system
spec:
  workloadSelector:
    labels:
      istio: ingressgateway
  
  configPatches:
  - applyTo: HTTP_FILTER
    match:
      context: GATEWAY
    patch:
      operation: INSERT_BEFORE
      value:
        name: envoy.filters.http.local_ratelimit
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.http.local_ratelimit.v3.LocalRateLimit
          stat_prefix: http_local_rate_limiter
          token_bucket:
            max_tokens: 100
            tokens_per_fill: 100
            fill_interval: 60s
          filter_enabled:
            runtime_key: local_rate_limit_enabled
            default_value:
              numerator: 100
              denominator: HUNDRED
          filter_enforced:
            runtime_key: local_rate_limit_enforced
            default_value:
              numerator: 100
              denominator: HUNDRED
          response_headers_to_add:
          - append: false
            header:
              key: x-rate-limit-remaining
              value: '%RATE_LIMIT_REMAINING%'
```

---

## Security Policies

### Authorization Policy (Istio)

```yaml
# service-mesh/istio/authz-policy.yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: api-authz
  namespace: default
spec:
  selector:
    matchLabels:
      app: api-service
  
  action: ALLOW
  
  rules:
  # Allow requests with valid JWT
  - from:
    - source:
        requestPrincipals: ["*"]
    to:
    - operation:
        methods: ["GET", "POST"]
        paths: ["/api/*"]
  
  # Allow internal service communication
  - from:
    - source:
        namespaces: ["default"]
    to:
    - operation:
        methods: ["*"]
  
  # Deny all other traffic (default DENY if no rules match)
---
# Deny policy for admin endpoints
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: deny-admin
  namespace: default
spec:
  selector:
    matchLabels:
      app: api-service
  
  action: DENY
  
  rules:
  - to:
    - operation:
        paths: ["/admin/*"]
    when:
    - key: source.namespace
      notValues: ["admin-namespace"]
```

### Request Authentication (JWT)

```yaml
# service-mesh/istio/jwt-auth.yaml
apiVersion: security.istio.io/v1beta1
kind: RequestAuthentication
metadata:
  name: jwt-auth
  namespace: default
spec:
  selector:
    matchLabels:
      app: api-service
  
  jwtRules:
  - issuer: "https://accounts.example.com"
    jwksUri: "https://accounts.example.com/.well-known/jwks.json"
    audiences:
    - "api.example.com"
    forwardOriginalToken: true
```

---

## Multi-Cluster Mesh

### Primary-Remote Cluster Setup (Istio)

```bash
# On primary cluster
istioctl install --set profile=default \
  --set values.global.meshID=mesh1 \
  --set values.global.multiCluster.clusterName=primary \
  --set values.global.network=network1

# On remote cluster
istioctl install --set profile=remote \
  --set values.global.meshID=mesh1 \
  --set values.global.multiCluster.clusterName=remote \
  --set values.global.network=network2

# Enable endpoint discovery
istioctl x create-remote-secret \
  --context=primary \
  --name=primary | \
  kubectl apply -f - --context=remote
```

---

## Observability

### Metrics

```bash
# Istio: Access Prometheus
kubectl port-forward -n istio-system svc/prometheus 9090:9090

# Linkerd: View metrics
linkerd viz stat deployment/api-service

# Top routes
linkerd viz top deployment/api-service
```

### Distributed Tracing

```bash
# Istio: Access Jaeger
istioctl dashboard jaeger

# Linkerd: Access Jaeger (if installed)
linkerd jaeger dashboard
```

### Service Graph

```bash
# Istio: Kiali dashboard
istioctl dashboard kiali

# Linkerd: Service topology
linkerd viz dashboard
```

---

## Best Practices

### 1. Gradual Rollout

```
1. Start with PERMISSIVE mTLS
2. Enable injection per namespace
3. Monitor for issues
4. Switch to STRICT mTLS
5. Enable advanced features gradually
```

### 2. Resource Management

✅ Set appropriate resource limits  
✅ Use HPA for control plane  
✅ Monitor proxy resource usage  
✅ Tune connection pools  

### 3. Security

✅ Always use STRICT mTLS in production  
✅ Implement least-privilege authz policies  
✅ Rotate certificates regularly  
✅ Monitor security events  

### 4. Performance

✅ Use connection pooling  
✅ Enable HTTP/2 where possible  
✅ Tune circuit breaker settings  
✅ Monitor latency metrics  

---

**Next Steps:**
- Configure GitOps: [GITOPS.md](GITOPS.md)
- Setup monitoring: [MONITORING.md](MONITORING.md)
- Implement security: [SECURITY.md](SECURITY.md)