# ⚡ Quick Start Guide

Get your infrastructure running in 5 minutes with local KinD cluster.

---

## Prerequisites

### Required Tools

```bash
# Check versions
kubectl version --client  # >= 1.28
helm version             # >= 3.12
kind version             # >= 0.20
docker --version         # >= 24.0
```

### Install Missing Tools

```bash
# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# KinD
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind && sudo mv ./kind /usr/local/bin/

# Flux CLI (optional for GitOps)
curl -s https://fluxcd.io/install.sh | sudo bash
```

---

## 🚀 Option 1: Automated Setup (Recommended)

### One Command Deployment

```bash
# Clone repository
git clone https://github.com/your-org/infra-transform.git
cd infra-transform

# Run full deployment
chmod +x transform.sh
./transform.sh full kind istio
```

**What this deploys:**
- ✅ KinD cluster (1 control-plane, 2 workers)
- ✅ Gateway API CRDs v1.1.0
- ✅ Istio service mesh (demo profile)
- ✅ Prometheus + Grafana monitoring
- ✅ Loki log aggregation
- ✅ Tempo distributed tracing
- ✅ Sample gateway and routes
- ✅ Custom transformation engine

**Time:** ~3-4 minutes

### Access Services

```bash
# Grafana Dashboard (admin/admin)
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Open: http://localhost:3000

# Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Open: http://localhost:9090

# Kiali Service Mesh Dashboard
istioctl dashboard kiali
# Opens automatically in browser

# Check deployments
kubectl get gateways,httproutes -A
kubectl get pods -n istio-system
kubectl get pods -n monitoring
```

---

## 🛠️ Option 2: Manual Step-by-Step

### Step 1: Create KinD Cluster (1 min)

```bash
cat <<EOF | kind create cluster --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: gateway-dev
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
- role: worker
- role: worker
EOF

# Verify cluster
kubectl cluster-info
kubectl get nodes
```

### Step 2: Install Gateway API (30 sec)

```bash
# Install Gateway API CRDs
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml

# Verify
kubectl get crd | grep gateway
kubectl api-resources | grep gateway.networking.k8s.io
```

### Step 3: Install Istio (2 min)

```bash
# Download Istio
curl -L https://istio.io/downloadIstio | sh -
cd istio-*/
export PATH=$PWD/bin:$PATH

# Install with demo profile
istioctl install --set profile=demo -y

# Enable auto-injection for default namespace
kubectl label namespace default istio-injection=enabled

# Verify
kubectl get pods -n istio-system
istioctl verify-install
```

### Step 4: Deploy Monitoring (2 min)

```bash
# Add Helm repos
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Create namespace
kubectl create namespace monitoring

# Install kube-prometheus-stack
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set grafana.adminPassword='admin'

# Install Loki
helm install loki grafana/loki-stack \
  --namespace monitoring \
  --set grafana.enabled=false

# Verify
kubectl get pods -n monitoring
```

### Step 5: Create Sample Gateway (1 min)

```bash
# Create GatewayClass
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: istio
spec:
  controllerName: istio.io/gateway-controller
EOF

# Create Gateway
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: demo-gateway
  namespace: default
spec:
  gatewayClassName: istio
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: All
EOF

# Deploy sample app
kubectl create deployment httpbin --image=kennethreitz/httpbin
kubectl expose deployment httpbin --port=80

# Create route
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: httpbin-route
spec:
  parentRefs:
  - name: demo-gateway
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: httpbin
      port: 80
EOF

# Verify
kubectl get gateways,httproutes
```

---

## ✅ Verification

### Check All Components

```bash
# Gateway API
kubectl get gatewayclasses
kubectl get gateways -A
kubectl get httproutes -A

# Service Mesh
kubectl get pods -n istio-system
istioctl proxy-status

# Monitoring
kubectl get pods -n monitoring
kubectl get servicemonitors -A

# Sample app
kubectl get pods
kubectl get svc
```

### Test Gateway

```bash
# Get gateway address
export GATEWAY_IP=$(kubectl get svc -n istio-system istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# If using KinD, use localhost
curl http://localhost/headers

# Should return HTTP 200 with headers
```

### Access Dashboards

```bash
# Grafana (admin/admin)
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 &

# Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090 &

# Kiali
istioctl dashboard kiali &

# All dashboards now accessible:
# - Grafana: http://localhost:3000
# - Prometheus: http://localhost:9090
# - Kiali: opens in browser
```

---

## 🎯 Next Steps

### 1. Explore Gateway Features

```bash
# Try advanced routing
kubectl apply -f gateway-api/routes/

# Enable transformations
kubectl apply -f transformations/envoy-filters/

# Configure mTLS
kubectl apply -f service-mesh/mtls-strict.yaml
```

### 2. Add Custom Transformations

See [TRANSFORMATIONS.md](TRANSFORMATIONS.md) for:
- API versioning
- Geographic routing
- Request/response modification
- Rate limiting

### 3. Setup GitOps

```bash
# Bootstrap FluxCD
export GITHUB_TOKEN="ghp_xxxxx"
flux bootstrap github \
  --owner=your-org \
  --repository=infra-config \
  --branch=main \
  --path=clusters/dev \
  --personal
```

### 4. Configure Monitoring

Import dashboards from [MONITORING.md](MONITORING.md):
- Gateway performance
- Service mesh traffic
- Business KPIs

### 5. Production Deployment

When ready, deploy to cloud:
- [Linode LKE](CLOUD-SETUP.md#linode-lke)
- [Google GKE](CLOUD-SETUP.md#google-gke)
- [OpenStack](CLOUD-SETUP.md#openstack)

---

## 🧹 Cleanup

### Delete Everything

```bash
# Delete KinD cluster
kind delete cluster --name gateway-dev

# Or keep cluster and remove components
kubectl delete namespace istio-system
kubectl delete namespace monitoring
kubectl delete gateways,httproutes -A
```

---

## 🐛 Troubleshooting

### Cluster Creation Fails

```bash
# Check Docker is running
docker ps

# Delete and retry
kind delete cluster --name gateway-dev
kind create cluster --name gateway-dev
```

### Gateway Not Working

```bash
# Check gateway status
kubectl describe gateway demo-gateway

# Check Istio ingress
kubectl get pods -n istio-system
kubectl logs -n istio-system -l app=istio-ingressgateway

# Check route attachment
kubectl get httproute httpbin-route -o yaml
```

### Monitoring Pods Failing

```bash
# Check resources
kubectl top nodes

# Increase Docker resources
# Docker Desktop: Settings → Resources → Memory (8GB+)

# Reinstall with smaller footprint
helm uninstall prometheus -n monitoring
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.resources.requests.memory=512Mi \
  --set prometheus.prometheusSpec.resources.limits.memory=1Gi
```

### Port Already in Use

```bash
# Check what's using port
sudo lsof -i :80
sudo lsof -i :443

# Kill processes or change KinD ports
# Edit extraPortMappings in cluster config
```

---

## 📚 Learn More

- **Gateway API**: [GATEWAY-API.md](GATEWAY-API.md)
- **Service Mesh**: [SERVICE-MESH.md](SERVICE-MESH.md)
- **Transformations**: [TRANSFORMATIONS.md](TRANSFORMATIONS.md)
- **Cloud Deployment**: [CLOUD-SETUP.md](CLOUD-SETUP.md)
- **GitOps**: [GITOPS.md](GITOPS.md)

---

**🎉 Congratulations!** You now have a complete Gateway API + Service Mesh environment running locally.
