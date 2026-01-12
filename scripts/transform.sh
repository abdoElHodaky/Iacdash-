#!/bin/bash

# Infrastructure Transform Script
# Automates deployment of Gateway API and Service Mesh infrastructure

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CLUSTER_NAME="${CLUSTER_NAME:-gateway-dev}"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi
    
    if ! command -v helm &> /dev/null; then
        missing_tools+=("helm")
    fi
    
    if ! command -v kind &> /dev/null; then
        missing_tools+=("kind")
    fi
    
    if ! command -v docker &> /dev/null; then
        missing_tools+=("docker")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install missing tools and try again."
        log_info "See quickstart_guide.md for installation instructions."
        exit 1
    fi
    
    log_success "All prerequisites satisfied"
}

# Create KinD cluster
create_kind_cluster() {
    log_info "Creating KinD cluster: $CLUSTER_NAME"
    
    if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
        log_warning "Cluster $CLUSTER_NAME already exists"
        return 0
    fi
    
    cat <<EOF | kind create cluster --name="$CLUSTER_NAME" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
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
    
    log_success "KinD cluster created successfully"
}

# Install Gateway API CRDs
install_gateway_api() {
    log_info "Installing Gateway API CRDs..."
    
    kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml
    
    # Wait for CRDs to be ready
    kubectl wait --for condition=established --timeout=60s crd/gatewayclasses.gateway.networking.k8s.io
    kubectl wait --for condition=established --timeout=60s crd/gateways.gateway.networking.k8s.io
    kubectl wait --for condition=established --timeout=60s crd/httproutes.gateway.networking.k8s.io
    
    log_success "Gateway API CRDs installed"
}

# Install Istio
install_istio() {
    log_info "Installing Istio..."
    
    # Download and install Istio
    if ! command -v istioctl &> /dev/null; then
        log_info "Downloading Istio..."
        curl -L https://istio.io/downloadIstio | sh -
        export PATH="$PWD/istio-*/bin:$PATH"
    fi
    
    # Install Istio
    istioctl install --set values.defaultRevision=default -y
    
    # Enable injection for default namespace
    kubectl label namespace default istio-injection=enabled --overwrite
    
    # Wait for Istio to be ready
    kubectl wait --for=condition=ready pod -l app=istiod -n istio-system --timeout=300s
    
    log_success "Istio installed successfully"
}

# Install monitoring stack
install_monitoring() {
    log_info "Installing monitoring stack..."
    
    # Add Helm repositories
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo update
    
    # Create monitoring namespace
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
    
    # Install Prometheus stack
    helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.retention=7d \
        --set grafana.adminPassword=admin \
        --wait
    
    log_success "Monitoring stack installed"
}

# Deploy basic Gateway API resources
deploy_gateway_resources() {
    log_info "Deploying basic Gateway API resources..."
    
    # Create basic GatewayClass if it doesn't exist
    if [ -f "$PROJECT_ROOT/gateway-api/gatewayclass.yaml" ]; then
        kubectl apply -f "$PROJECT_ROOT/gateway-api/gatewayclass.yaml"
    else
        log_warning "No gatewayclass.yaml found, creating basic one..."
        cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: istio
spec:
  controllerName: istio.io/gateway-controller
EOF
    fi
    
    # Apply other Gateway API resources if they exist
    if [ -d "$PROJECT_ROOT/gateway-api" ]; then
        find "$PROJECT_ROOT/gateway-api" -name "*.yaml" -exec kubectl apply -f {} \;
    fi
    
    log_success "Gateway API resources deployed"
}

# Show cluster information
show_cluster_info() {
    log_info "Cluster Information:"
    echo
    echo "Cluster: $CLUSTER_NAME"
    echo "Context: kind-$CLUSTER_NAME"
    echo
    
    log_info "Gateway API Resources:"
    kubectl get gatewayclasses,gateways,httproutes -A 2>/dev/null || true
    echo
    
    log_info "Istio Components:"
    kubectl get pods -n istio-system 2>/dev/null || true
    echo
    
    log_info "Monitoring Components:"
    kubectl get pods -n monitoring 2>/dev/null || true
    echo
    
    log_info "Access Information:"
    echo "Grafana: kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
    echo "Prometheus: kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
    echo "Default credentials: admin/admin"
}

# Main deployment function
deploy_full() {
    log_info "Starting full deployment..."
    
    check_prerequisites
    create_kind_cluster
    install_gateway_api
    install_istio
    install_monitoring
    deploy_gateway_resources
    
    log_success "Full deployment completed!"
    show_cluster_info
}

# Cleanup function
cleanup() {
    log_info "Cleaning up cluster: $CLUSTER_NAME"
    kind delete cluster --name="$CLUSTER_NAME"
    log_success "Cleanup completed"
}

# Help function
show_help() {
    cat <<EOF
Infrastructure Transform Script

Usage: $0 [COMMAND] [OPTIONS]

Commands:
  full [PROVIDER] [MESH]    Deploy full stack (default: kind istio)
  kind                      Create KinD cluster only
  gateway-api               Install Gateway API CRDs only
  istio                     Install Istio only
  monitoring                Install monitoring stack only
  cleanup                   Delete KinD cluster
  info                      Show cluster information
  help                      Show this help

Examples:
  $0 full kind istio        # Full deployment with KinD and Istio
  $0 kind                   # Create KinD cluster only
  $0 cleanup                # Delete cluster

Environment Variables:
  CLUSTER_NAME              Name of the cluster (default: gateway-dev)

EOF
}

# Main script logic
main() {
    case "${1:-help}" in
        "full")
            PROVIDER="${2:-kind}"
            MESH="${3:-istio}"
            if [ "$PROVIDER" = "kind" ] && [ "$MESH" = "istio" ]; then
                deploy_full
            else
                log_error "Only 'kind' provider and 'istio' mesh are currently supported"
                log_info "Full multi-cloud support coming in Phase 3"
                exit 1
            fi
            ;;
        "kind")
            check_prerequisites
            create_kind_cluster
            ;;
        "gateway-api")
            install_gateway_api
            ;;
        "istio")
            install_istio
            ;;
        "monitoring")
            install_monitoring
            ;;
        "cleanup")
            cleanup
            ;;
        "info")
            show_cluster_info
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            log_error "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
