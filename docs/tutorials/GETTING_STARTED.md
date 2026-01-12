# 🚀 Getting Started with Iacdash-

This tutorial will guide you through deploying a complete Gateway API and Service Mesh infrastructure in under 10 minutes.

## 📋 Prerequisites

Before starting, ensure you have:

- **Docker** (20.10+)
- **kubectl** (1.28+)
- **kind** (0.20+)
- **Terraform** (1.6+) - for cloud deployments
- **Helm** (3.12+)

## 🎯 Quick Start (Local Development)

### Step 1: Clone and Setup

```bash
# Clone the repository
git clone https://github.com/abdoElHodaky/Iacdash-.git
cd Iacdash-

# Make scripts executable
chmod +x scripts/transform.sh
```

### Step 2: Deploy Local Infrastructure

```bash
# Deploy complete stack (KinD + Gateway API + Istio + Monitoring)
./scripts/transform.sh full kind istio

# This will:
# ✅ Create KinD cluster with 3 nodes
# ✅ Install Gateway API CRDs
# ✅ Deploy Istio service mesh
# ✅ Setup Prometheus + Grafana monitoring
# ✅ Deploy demo applications
```

### Step 3: Verify Deployment

```bash
# Check cluster status
kubectl get nodes

# Verify Gateway API resources
kubectl get gateways,httproutes -A

# Check Istio installation
kubectl get pods -n istio-system

# Verify monitoring stack
kubectl get pods -n monitoring
```

### Step 4: Access Services

```bash
# Access Grafana dashboard
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Open: http://localhost:3000 (admin/admin)

# Access demo application
kubectl port-forward -n default svc/httpbin 8080:8000
# Open: http://localhost:8080

# Access Jaeger tracing (if enabled)
kubectl port-forward -n tracing svc/jaeger 16686:16686
# Open: http://localhost:16686
```

## 🌐 Cloud Deployment

### Option 1: Linode LKE

```bash
# Navigate to Linode example
cd terraform/examples/linode-production

# Copy and customize configuration
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Linode token and preferences

# Deploy infrastructure
terraform init
terraform plan
terraform apply

# Configure kubectl
export KUBECONFIG=~/.kube/config-lke-gateway-production
```

### Option 2: Google GKE

```bash
# Navigate to GKE example
cd terraform/examples/gke-production

# Set up GCP authentication
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID

# Copy and customize configuration
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project settings

# Deploy infrastructure
terraform init
terraform plan
terraform apply

# Configure kubectl
gcloud container clusters get-credentials gateway-production --region us-central1
```

## 🔧 Configuration Options

### Environment Variables

```bash
# Customize deployment
export CLUSTER_ENV="dev"           # Environment name
export ISTIO_VERSION="1.20.1"      # Istio version
export MONITORING_RETENTION="30d"  # Prometheus retention
export GRAFANA_PASSWORD="secure"   # Grafana admin password
```

### Advanced Features

```bash
# Enable distributed tracing
./scripts/transform.sh monitoring jaeger

# Deploy security policies
kubectl apply -f security/policies/
kubectl apply -f security/network-policies/

# Run performance tests
kubectl apply -f testing/load-testing/gateway-stress-test.yaml
```

## 🔍 Verification and Testing

### Health Checks

```bash
# Check all components
kubectl get pods -A | grep -E "(Running|Completed)"

# Verify Gateway API functionality
curl -H "Host: demo.dev.local" http://localhost/get

# Test service mesh mTLS
kubectl exec -n default deploy/httpbin -- curl -s http://httpbin:8000/get
```

### Performance Testing

```bash
# Run load test
k6 run testing/performance/k6-load-test.js

# Monitor metrics in Grafana
# Navigate to Gateway API Overview dashboard
```

## 🛠️ Troubleshooting

### Common Issues

1. **KinD cluster creation fails**
   ```bash
   # Clean up and retry
   kind delete cluster --name gateway-dev
   ./scripts/transform.sh cleanup
   ./scripts/transform.sh full kind istio
   ```

2. **Gateway not accessible**
   ```bash
   # Check gateway status
   kubectl describe gateway default-gateway -n istio-ingress
   
   # Verify LoadBalancer service
   kubectl get svc -n istio-ingress
   ```

3. **Monitoring not working**
   ```bash
   # Check Prometheus targets
   kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
   # Open: http://localhost:9090/targets
   ```

### Debug Commands

```bash
# View logs
kubectl logs -n istio-system deployment/istiod
kubectl logs -n monitoring deployment/prometheus-kube-prometheus-operator

# Check resource usage
kubectl top nodes
kubectl top pods -A
```

## 🎓 Next Steps

1. **Explore Advanced Features**
   - [Multi-cluster setup](./MULTI_CLUSTER.md)
   - [Custom transformations](./TRANSFORMATIONS.md)
   - [Security policies](./SECURITY.md)

2. **Production Deployment**
   - [Production checklist](./PRODUCTION.md)
   - [Monitoring setup](./MONITORING.md)
   - [Backup strategies](./BACKUP.md)

3. **Development Workflow**
   - [GitOps with FluxCD](./GITOPS.md)
   - [CI/CD integration](./CICD.md)
   - [Testing strategies](./TESTING.md)

## 📚 Additional Resources

- [Architecture Overview](../README.md#architecture)
- [Configuration Reference](./CONFIGURATION.md)
- [API Documentation](./API.md)
- [Contributing Guide](./CONTRIBUTING.md)

---

**Need help?** Open an issue or join our community discussions!

