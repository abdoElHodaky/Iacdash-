# 🔐 Security & Compliance Guide

Complete guide for implementing security best practices, compliance, and zero-trust architecture.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Zero-Trust Architecture](#zero-trust-architecture)
- [Network Policies](#network-policies)
- [Pod Security](#pod-security)
- [Secrets Management](#secrets-management)
- [RBAC Configuration](#rbac-configuration)
- [Certificate Management](#certificate-management)
- [Security Scanning](#security-scanning)
- [Compliance & Audit](#compliance--audit)
- [Best Practices](#best-practices)

---

## Overview

Security layers in Kubernetes Gateway API + Service Mesh:

```
┌──────────────────────────────────────────┐
│         External Traffic                  │
└──────────────┬───────────────────────────┘
               │
┌──────────────▼───────────────────────────┐
│      DDoS Protection / WAF               │
│      (Cloud Armor, Cloudflare)           │
└──────────────┬───────────────────────────┘
               │
┌──────────────▼───────────────────────────┐
│      Gateway API (TLS Termination)       │
│      • Certificate Management            │
│      • Rate Limiting                     │
│      • Request Authentication            │
└──────────────┬───────────────────────────┘
               │
┌──────────────▼───────────────────────────┐
│      Service Mesh (mTLS)                 │
│      • Automatic Encryption              │
│      • Authorization Policies            │
│      • Traffic Control                   │
└──────────────┬───────────────────────────┘
               │
┌──────────────▼───────────────────────────┐
│      Network Policies                    │
│      • Namespace Isolation               │
│      • Micro-segmentation                │
└──────────────┬───────────────────────────┘
               │
┌──────────────▼───────────────────────────┐
│      Pod Security Standards              │
│      • Restricted Execution              │
│      • No Root Containers                │
│      • Read-only Filesystems             │
└──────────────────────────────────────────┘
```

---

## Zero-Trust Architecture

### Principles

1. **Never Trust, Always Verify**: Authenticate every request
2. **Least Privilege**: Minimum necessary permissions
3. **Assume Breach**: Defense in depth
4. **Verify Explicitly**: Use identity and context
5. **Micro-Segmentation**: Isolate workloads

### Implementation

```yaml
# Zero-trust configuration with Istio
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system
spec:
  mtls:
    mode: STRICT  # Enforce mTLS everywhere

---
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: deny-all
  namespace: default
spec:
  {}  # Default deny all traffic

---
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-specific
  namespace: default
spec:
  selector:
    matchLabels:
      app: api-service
  action: ALLOW
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/default/sa/frontend"]
    to:
    - operation:
        methods: ["GET", "POST"]
        paths: ["/api/*"]
```

---

## Network Policies

### Default Deny All

```yaml
# security/network-policies/default-deny.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

### Allow Gateway Traffic

```yaml
# security/network-policies/allow-gateway.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-gateway
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: api-service
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: istio-system
    ports:
    - protocol: TCP
      port: 8080
```

### Allow Inter-Service Communication

```yaml
# security/network-policies/allow-inter-service.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-inter-service
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: backend-service
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: api-service
    ports:
    - protocol: TCP
      port: 8080
```

### Allow Egress to External Services

```yaml
# security/network-policies/allow-egress.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-egress
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: api-service
  policyTypes:
  - Egress
  egress:
  # Allow DNS
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
  
  # Allow HTTPS to external services
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 443
  
  # Allow specific external IPs
  - to:
    - ipBlock:
        cidr: 203.0.113.0/24  # External API
    ports:
    - protocol: TCP
      port: 443
```

### Cilium Network Policy (Advanced)

```yaml
# security/network-policies/cilium-policy.yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: api-service-policy
  namespace: default
spec:
  endpointSelector:
    matchLabels:
      app: api-service
  
  ingress:
  # Allow from gateway
  - fromEndpoints:
    - matchLabels:
        app: istio-ingressgateway
        k8s:io.kubernetes.pod.namespace: istio-system
    toPorts:
    - ports:
      - port: "8080"
        protocol: TCP
  
  egress:
  # Allow DNS
  - toEndpoints:
    - matchLabels:
        k8s:io.kubernetes.pod.namespace: kube-system
        k8s-app: kube-dns
    toPorts:
    - ports:
      - port: "53"
        protocol: UDP
  
  # Allow to backend
  - toEndpoints:
    - matchLabels:
        app: backend-service
    toPorts:
    - ports:
      - port: "8080"
        protocol: TCP
  
  # Allow external HTTPS
  - toFQDNs:
    - matchName: "api.example.com"
    toPorts:
    - ports:
      - port: "443"
        protocol: TCP
```

---

## Pod Security

### Pod Security Standards

```yaml
# security/pod-security/namespace-labels.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    # Enforce restricted profile
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    
    # Audit and warn modes
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### Secure Pod Template

```yaml
# security/pod-security/secure-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secure-app
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: secure-app
  template:
    metadata:
      labels:
        app: secure-app
    spec:
      # Service account
      serviceAccountName: secure-app
      automountServiceAccountToken: false
      
      # Security context for pod
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 3000
        fsGroup: 2000
        seccompProfile:
          type: RuntimeDefault
      
      containers:
      - name: app
        image: ghcr.io/org/secure-app:v1.0.0
        
        # Security context for container
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          runAsNonRoot: true
          runAsUser: 1000
          capabilities:
            drop:
            - ALL
        
        # Resources
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
        
        # Volume mounts
        volumeMounts:
        - name: tmp
          mountPath: /tmp
        - name: cache
          mountPath: /app/cache
      
      volumes:
      - name: tmp
        emptyDir: {}
      - name: cache
        emptyDir: {}
```

### OPA Gatekeeper Policies

```yaml
# security/opa-gatekeeper/require-non-root.yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequirenonroot
spec:
  crd:
    spec:
      names:
        kind: K8sRequireNonRoot
  targets:
  - target: admission.k8s.gatekeeper.sh
    rego: |
      package k8srequirenonroot
      
      violation[{"msg": msg}] {
        not input.review.object.spec.securityContext.runAsNonRoot
        msg := "Containers must not run as root"
      }
---
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequireNonRoot
metadata:
  name: must-run-as-non-root
spec:
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment", "StatefulSet"]
    namespaces:
    - production
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
kubectl create secret generic db-credentials \
  --from-literal=username=admin \
  --from-literal=password=SuperSecure123! \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > sealed-secret.yaml

# Apply (safe to commit to Git)
kubectl apply -f sealed-secret.yaml
```

### External Secrets Operator

```yaml
# security/secrets/external-secret-operator.yaml
# Install operator first:
# helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace

# SecretStore for Vault
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
          serviceAccountRef:
            name: app-service-account

---
# ExternalSecret
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-credentials
  namespace: default
spec:
  refreshInterval: 1h
  
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  
  target:
    name: app-credentials
    creationPolicy: Owner
  
  data:
  - secretKey: api-key
    remoteRef:
      key: app-service
      property: api_key
  
  - secretKey: database-url
    remoteRef:
      key: app-service
      property: database_url
```

### SOPS Encryption

```bash
# Install SOPS
brew install sops

# Generate Age key
age-keygen -o age.key

# Encrypt secret
sops --age $(cat age.key | grep public | cut -d: -f2) \
  --encrypt secret.yaml > secret.enc.yaml

# Configure FluxCD decryption
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=age.key

# Reference in Kustomization
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  decryption:
    provider: sops
    secretRef:
      name: sops-age
```

---

## RBAC Configuration

### Service Account

```yaml
# security/rbac/service-account.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: api-service
  namespace: default
automountServiceAccountToken: false
```

### Role and RoleBinding

```yaml
# security/rbac/role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: api-service-role
  namespace: default
rules:
# Allow reading ConfigMaps
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list", "watch"]

# Allow reading Secrets
- apiGroups: [""]
  resources: ["secrets"]
  resourceNames: ["api-credentials"]
  verbs: ["get"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: api-service-binding
  namespace: default
subjects:
- kind: ServiceAccount
  name: api-service
  namespace: default
roleRef:
  kind: Role
  name: api-service-role
  apiGroup: rbac.authorization.k8s.io
```

### ClusterRole for Gateway

```yaml
# security/rbac/gateway-clusterrole.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: gateway-controller
rules:
# Gateway API resources
- apiGroups: ["gateway.networking.k8s.io"]
  resources: ["gatewayclasses", "gateways", "httproutes"]
  verbs: ["get", "list", "watch", "update", "patch"]

# Gateway status
- apiGroups: ["gateway.networking.k8s.io"]
  resources: ["gateways/status", "httproutes/status"]
  verbs: ["update"]

# Services and endpoints
- apiGroups: [""]
  resources: ["services", "endpoints"]
  verbs: ["get", "list", "watch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: gateway-controller-binding
subjects:
- kind: ServiceAccount
  name: gateway-controller
  namespace: istio-system
roleRef:
  kind: ClusterRole
  name: gateway-controller
  apiGroup: rbac.authorization.k8s.io
```

---

## Certificate Management

### Install cert-manager

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Verify
kubectl get pods -n cert-manager
```

### ClusterIssuer for Let's Encrypt

```yaml
# security/certificates/letsencrypt-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    
    privateKeySecretRef:
      name: letsencrypt-prod
    
    solvers:
    # HTTP-01 challenge
    - http01:
        ingress:
          class: istio
    
    # DNS-01 challenge (for wildcards)
    - dns01:
        cloudflare:
          email: admin@example.com
          apiTokenSecretRef:
            name: cloudflare-api-token
            key: api-token
      selector:
        dnsNames:
        - "*.example.com"
```

### Certificate Resource

```yaml
# security/certificates/wildcard-cert.yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-example-com
  namespace: default
spec:
  secretName: wildcard-tls
  
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  
  dnsNames:
  - "example.com"
  - "*.example.com"
  
  # Renewal before expiry
  renewBefore: 720h  # 30 days
```

### Automatic Certificate Rotation

```yaml
# Gateway with automatic cert
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: production-gateway
  namespace: default
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  gatewayClassName: istio
  listeners:
  - name: https
    protocol: HTTPS
    port: 443
    hostname: "*.example.com"
    tls:
      mode: Terminate
      certificateRefs:
      - name: wildcard-tls
```

---

## Security Scanning

### Trivy Vulnerability Scanning

```bash
# Install Trivy
brew install trivy

# Scan image
trivy image ghcr.io/org/api-service:v1.0.0

# Scan in CI/CD
trivy image --severity HIGH,CRITICAL \
  --exit-code 1 \
  ghcr.io/org/api-service:v1.0.0

# Scan Kubernetes manifests
trivy config ./kubernetes/

# Scan running cluster
trivy k8s --report summary cluster
```

### Falco Runtime Security

```bash
# Install Falco
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm install falco falcosecurity/falco \
  --namespace falco --create-namespace

# Custom rules
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: falco-rules
  namespace: falco
data:
  custom-rules.yaml: |
    - rule: Unauthorized Process in Container
      desc: Detect unauthorized processes
      condition: >
        spawned_process and
        container and
        not proc.name in (allowed_processes)
      output: >
        Unauthorized process started
        (user=%user.name command=%proc.cmdline container=%container.name)
      priority: WARNING
EOF
```

### Kyverno Policy Engine

```yaml
# security/kyverno/require-labels.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-labels
spec:
  validationFailureAction: enforce
  rules:
  - name: check-for-labels
    match:
      any:
      - resources:
          kinds:
          - Deployment
    validate:
      message: "label 'app' is required"
      pattern:
        metadata:
          labels:
            app: "?*"
---
# Require image signature
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-image-signature
spec:
  validationFailureAction: enforce
  rules:
  - name: verify-signature
    match:
      any:
      - resources:
          kinds:
          - Pod
    verifyImages:
    - imageReferences:
      - "ghcr.io/org/*"
      attestors:
      - entries:
        - keys:
            publicKeys: |-
              -----BEGIN PUBLIC KEY-----
              YOUR_PUBLIC_KEY_HERE
              -----END PUBLIC KEY-----
```

---

## Compliance & Audit

### Audit Logging

```yaml
# security/audit/audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
# Log all requests at Metadata level
- level: Metadata
  omitStages:
  - RequestReceived

# Log secrets at Request level (without body)
- level: Request
  resources:
  - group: ""
    resources: ["secrets"]

# Log authentication at RequestResponse level
- level: RequestResponse
  users: ["system:anonymous"]
  
# Don't log read-only requests
- level: None
  verbs: ["get", "list", "watch"]
```

### Compliance Scanning

```bash
# Install kube-bench
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml

# View results
kubectl logs -f job/kube-bench

# Run specific checks
kubectl run kube-bench --image=aquasec/kube-bench:latest \
  --restart=Never \
  -- run --targets master
```

### Audit Trail with FluxCD

```bash
# View what changed
flux events --for Kustomization/infrastructure

# Check who made changes
git log --oneline infrastructure/

# Reconciliation history
kubectl get events -n flux-system
```

---

## Best Practices

### 1. Defense in Depth

```
Layer 1: Network Security (CloudFlare, WAF)
Layer 2: Gateway Security (Rate limiting, TLS)
Layer 3: Service Mesh (mTLS, Authorization)
Layer 4: Network Policies (Micro-segmentation)
Layer 5: Pod Security (Non-root, Read-only FS)
Layer 6: RBAC (Least privilege)
Layer 7: Secrets (Encryption at rest)
Layer 8: Monitoring (Audit logs, Alerts)
```

### 2. Security Checklist

✅ mTLS enabled in service mesh  
✅ Network policies enforce segmentation  
✅ Pods run as non-root  
✅ Read-only root filesystem  
✅ Secrets encrypted (Sealed Secrets/SOPS)  
✅ RBAC with least privilege  
✅ Certificate auto-rotation  
✅ Vulnerability scanning in CI/CD  
✅ Runtime security (Falco)  
✅ Audit logging enabled  

### 3. Incident Response

```bash
# Check for compromised pods
kubectl get pods --all-namespaces -o json | \
  jq '.items[] | select(.spec.containers[].securityContext.privileged==true)'

# View audit logs
kubectl logs -n kube-system kube-apiserver-xxx | grep audit

# Check RBAC permissions
kubectl auth can-i --list --as=system:serviceaccount:default:api-service

# Review network connections
kubectl exec -it pod-name -- netstat -an
```

---

**Next:** [TROUBLESHOOTING.md](TROUBLESHOOTING.md)