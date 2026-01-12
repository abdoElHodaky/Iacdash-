#!/bin/bash
set -euo pipefail

# Kubernetes Cluster Debug Script
# Comprehensive debugging tool for Gateway API and Service Mesh issues

# Configuration
OUTPUT_DIR="${OUTPUT_DIR:-./debug-output}"
NAMESPACE="${NAMESPACE:-}"
INCLUDE_LOGS="${INCLUDE_LOGS:-true}"
LOG_LINES="${LOG_LINES:-1000}"
INCLUDE_EVENTS="${INCLUDE_EVENTS:-true}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Create output directory
setup_output_dir() {
    local timestamp=$(date +%Y%m%d-%H%M%S)
    OUTPUT_DIR="$OUTPUT_DIR/debug-$timestamp"
    mkdir -p "$OUTPUT_DIR"
    log_info "Debug output will be saved to: $OUTPUT_DIR"
}

# Check cluster connectivity
check_cluster_connectivity() {
    log_info "Checking cluster connectivity..."
    
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    kubectl cluster-info > "$OUTPUT_DIR/cluster-info.txt"
    kubectl version --client=false > "$OUTPUT_DIR/cluster-version.txt" 2>&1 || true
    
    log_info "Cluster connectivity check completed"
}

# Collect node information
collect_node_info() {
    log_info "Collecting node information..."
    
    local node_dir="$OUTPUT_DIR/nodes"
    mkdir -p "$node_dir"
    
    # Node status
    kubectl get nodes -o wide > "$node_dir/nodes-wide.txt"
    kubectl get nodes -o yaml > "$node_dir/nodes-yaml.yaml"
    kubectl describe nodes > "$node_dir/nodes-describe.txt"
    
    # Node conditions and taints
    kubectl get nodes -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[-1].type,REASON:.status.conditions[-1].reason > "$node_dir/node-conditions.txt"
    kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints > "$node_dir/node-taints.txt"
    
    # Node resource usage (if metrics-server is available)
    if kubectl top nodes &> /dev/null; then
        kubectl top nodes > "$node_dir/node-metrics.txt"
    fi
    
    log_info "Node information collected"
}

# Collect namespace information
collect_namespace_info() {
    log_info "Collecting namespace information..."
    
    local ns_dir="$OUTPUT_DIR/namespaces"
    mkdir -p "$ns_dir"
    
    kubectl get namespaces -o wide > "$ns_dir/namespaces.txt"
    kubectl get namespaces -o yaml > "$ns_dir/namespaces-yaml.yaml"
    
    # Resource quotas and limits
    kubectl get resourcequotas --all-namespaces > "$ns_dir/resource-quotas.txt" 2>/dev/null || true
    kubectl get limitranges --all-namespaces > "$ns_dir/limit-ranges.txt" 2>/dev/null || true
    
    log_info "Namespace information collected"
}

# Collect Gateway API resources
collect_gateway_api_info() {
    log_info "Collecting Gateway API information..."
    
    local gw_dir="$OUTPUT_DIR/gateway-api"
    mkdir -p "$gw_dir"
    
    # Check if Gateway API CRDs are installed
    if ! kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null; then
        log_warn "Gateway API CRDs not found"
        echo "Gateway API CRDs not installed" > "$gw_dir/not-installed.txt"
        return 0
    fi
    
    # Gateway Classes
    kubectl get gatewayclasses -o wide > "$gw_dir/gatewayclasses.txt" 2>/dev/null || true
    kubectl get gatewayclasses -o yaml > "$gw_dir/gatewayclasses-yaml.yaml" 2>/dev/null || true
    kubectl describe gatewayclasses > "$gw_dir/gatewayclasses-describe.txt" 2>/dev/null || true
    
    # Gateways
    kubectl get gateways --all-namespaces -o wide > "$gw_dir/gateways.txt" 2>/dev/null || true
    kubectl get gateways --all-namespaces -o yaml > "$gw_dir/gateways-yaml.yaml" 2>/dev/null || true
    kubectl describe gateways --all-namespaces > "$gw_dir/gateways-describe.txt" 2>/dev/null || true
    
    # HTTPRoutes
    kubectl get httproutes --all-namespaces -o wide > "$gw_dir/httproutes.txt" 2>/dev/null || true
    kubectl get httproutes --all-namespaces -o yaml > "$gw_dir/httproutes-yaml.yaml" 2>/dev/null || true
    kubectl describe httproutes --all-namespaces > "$gw_dir/httproutes-describe.txt" 2>/dev/null || true
    
    # Other route types
    kubectl get grpcroutes --all-namespaces -o wide > "$gw_dir/grpcroutes.txt" 2>/dev/null || true
    kubectl get tcproutes --all-namespaces -o wide > "$gw_dir/tcproutes.txt" 2>/dev/null || true
    kubectl get tlsroutes --all-namespaces -o wide > "$gw_dir/tlsroutes.txt" 2>/dev/null || true
    
    # Reference grants
    kubectl get referencegrants --all-namespaces -o wide > "$gw_dir/referencegrants.txt" 2>/dev/null || true
    kubectl get referencegrants --all-namespaces -o yaml > "$gw_dir/referencegrants-yaml.yaml" 2>/dev/null || true
    
    log_info "Gateway API information collected"
}

# Collect Istio service mesh information
collect_istio_info() {
    log_info "Collecting Istio service mesh information..."
    
    local istio_dir="$OUTPUT_DIR/istio"
    mkdir -p "$istio_dir"
    
    # Check if Istio is installed
    if ! kubectl get namespace istio-system &> /dev/null; then
        log_warn "Istio namespace not found"
        echo "Istio not installed" > "$istio_dir/not-installed.txt"
        return 0
    fi
    
    # Istio installation status
    if command -v istioctl &> /dev/null; then
        istioctl version > "$istio_dir/istio-version.txt" 2>&1 || true
        istioctl proxy-status > "$istio_dir/proxy-status.txt" 2>&1 || true
        istioctl analyze > "$istio_dir/analyze.txt" 2>&1 || true
    fi
    
    # Istio CRDs and resources
    kubectl get crd | grep istio > "$istio_dir/istio-crds.txt" 2>/dev/null || true
    
    # Virtual Services
    kubectl get virtualservices --all-namespaces -o wide > "$istio_dir/virtualservices.txt" 2>/dev/null || true
    kubectl get virtualservices --all-namespaces -o yaml > "$istio_dir/virtualservices-yaml.yaml" 2>/dev/null || true
    
    # Destination Rules
    kubectl get destinationrules --all-namespaces -o wide > "$istio_dir/destinationrules.txt" 2>/dev/null || true
    kubectl get destinationrules --all-namespaces -o yaml > "$istio_dir/destinationrules-yaml.yaml" 2>/dev/null || true
    
    # Istio Gateways
    kubectl get gateways.networking.istio.io --all-namespaces -o wide > "$istio_dir/istio-gateways.txt" 2>/dev/null || true
    kubectl get gateways.networking.istio.io --all-namespaces -o yaml > "$istio_dir/istio-gateways-yaml.yaml" 2>/dev/null || true
    
    # Service Entries
    kubectl get serviceentries --all-namespaces -o wide > "$istio_dir/serviceentries.txt" 2>/dev/null || true
    
    # Envoy Filters
    kubectl get envoyfilters --all-namespaces -o wide > "$istio_dir/envoyfilters.txt" 2>/dev/null || true
    kubectl get envoyfilters --all-namespaces -o yaml > "$istio_dir/envoyfilters-yaml.yaml" 2>/dev/null || true
    
    # Peer Authentication
    kubectl get peerauthentications --all-namespaces -o wide > "$istio_dir/peerauthentications.txt" 2>/dev/null || true
    
    # Authorization Policies
    kubectl get authorizationpolicies --all-namespaces -o wide > "$istio_dir/authorizationpolicies.txt" 2>/dev/null || true
    
    # Istio system pods
    kubectl get pods -n istio-system -o wide > "$istio_dir/istio-pods.txt"
    kubectl describe pods -n istio-system > "$istio_dir/istio-pods-describe.txt"
    
    log_info "Istio information collected"
}

# Collect certificate information
collect_cert_info() {
    log_info "Collecting certificate information..."
    
    local cert_dir="$OUTPUT_DIR/certificates"
    mkdir -p "$cert_dir"
    
    # cert-manager resources
    if kubectl get namespace cert-manager &> /dev/null; then
        kubectl get certificates --all-namespaces -o wide > "$cert_dir/certificates.txt" 2>/dev/null || true
        kubectl get certificates --all-namespaces -o yaml > "$cert_dir/certificates-yaml.yaml" 2>/dev/null || true
        kubectl describe certificates --all-namespaces > "$cert_dir/certificates-describe.txt" 2>/dev/null || true
        
        kubectl get certificaterequests --all-namespaces -o wide > "$cert_dir/certificaterequests.txt" 2>/dev/null || true
        kubectl get issuers --all-namespaces -o wide > "$cert_dir/issuers.txt" 2>/dev/null || true
        kubectl get clusterissuers -o wide > "$cert_dir/clusterissuers.txt" 2>/dev/null || true
        
        # cert-manager pods
        kubectl get pods -n cert-manager -o wide > "$cert_dir/cert-manager-pods.txt"
        kubectl describe pods -n cert-manager > "$cert_dir/cert-manager-pods-describe.txt"
    fi
    
    # TLS secrets
    kubectl get secrets --all-namespaces --field-selector type=kubernetes.io/tls -o wide > "$cert_dir/tls-secrets.txt" 2>/dev/null || true
    
    log_info "Certificate information collected"
}

# Collect monitoring information
collect_monitoring_info() {
    log_info "Collecting monitoring information..."
    
    local mon_dir="$OUTPUT_DIR/monitoring"
    mkdir -p "$mon_dir"
    
    # Prometheus
    if kubectl get namespace monitoring &> /dev/null; then
        kubectl get pods -n monitoring -o wide > "$mon_dir/monitoring-pods.txt"
        kubectl get services -n monitoring -o wide > "$mon_dir/monitoring-services.txt"
        kubectl get servicemonitors --all-namespaces -o wide > "$mon_dir/servicemonitors.txt" 2>/dev/null || true
        kubectl get prometheusrules --all-namespaces -o wide > "$mon_dir/prometheusrules.txt" 2>/dev/null || true
    fi
    
    # Metrics (if available)
    if kubectl top pods --all-namespaces &> /dev/null; then
        kubectl top pods --all-namespaces > "$mon_dir/pod-metrics.txt"
    fi
    
    log_info "Monitoring information collected"
}

# Collect pod information
collect_pod_info() {
    log_info "Collecting pod information..."
    
    local pod_dir="$OUTPUT_DIR/pods"
    mkdir -p "$pod_dir"
    
    # All pods
    kubectl get pods --all-namespaces -o wide > "$pod_dir/all-pods.txt"
    kubectl get pods --all-namespaces -o yaml > "$pod_dir/all-pods-yaml.yaml"
    
    # Failed/problematic pods
    kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded > "$pod_dir/problematic-pods.txt" 2>/dev/null || true
    
    # Pod resource usage
    if kubectl top pods --all-namespaces &> /dev/null; then
        kubectl top pods --all-namespaces --containers > "$pod_dir/pod-resource-usage.txt"
    fi
    
    log_info "Pod information collected"
}

# Collect events
collect_events() {
    if [[ "$INCLUDE_EVENTS" != "true" ]]; then
        return 0
    fi
    
    log_info "Collecting cluster events..."
    
    local events_dir="$OUTPUT_DIR/events"
    mkdir -p "$events_dir"
    
    # All events
    kubectl get events --all-namespaces --sort-by='.lastTimestamp' > "$events_dir/all-events.txt"
    
    # Warning events
    kubectl get events --all-namespaces --field-selector type=Warning --sort-by='.lastTimestamp' > "$events_dir/warning-events.txt"
    
    # Recent events (last hour)
    kubectl get events --all-namespaces --field-selector involvedObject.kind!=Node --sort-by='.lastTimestamp' | tail -100 > "$events_dir/recent-events.txt"
    
    log_info "Events collected"
}

# Collect logs
collect_logs() {
    if [[ "$INCLUDE_LOGS" != "true" ]]; then
        return 0
    fi
    
    log_info "Collecting pod logs..."
    
    local logs_dir="$OUTPUT_DIR/logs"
    mkdir -p "$logs_dir"
    
    # System component logs
    for ns in kube-system istio-system flux-system monitoring cert-manager external-secrets-system; do
        if kubectl get namespace "$ns" &> /dev/null; then
            local ns_logs_dir="$logs_dir/$ns"
            mkdir -p "$ns_logs_dir"
            
            kubectl get pods -n "$ns" -o name | while read pod; do
                local pod_name=$(basename "$pod")
                log_debug "Collecting logs for $ns/$pod_name"
                kubectl logs -n "$ns" "$pod_name" --tail="$LOG_LINES" > "$ns_logs_dir/$pod_name.log" 2>&1 || true
                kubectl logs -n "$ns" "$pod_name" --previous --tail="$LOG_LINES" > "$ns_logs_dir/$pod_name-previous.log" 2>&1 || true
            done
        fi
    done
    
    log_info "Logs collected"
}

# Collect network information
collect_network_info() {
    log_info "Collecting network information..."
    
    local net_dir="$OUTPUT_DIR/network"
    mkdir -p "$net_dir"
    
    # Services
    kubectl get services --all-namespaces -o wide > "$net_dir/services.txt"
    kubectl get endpoints --all-namespaces -o wide > "$net_dir/endpoints.txt"
    
    # Network policies
    kubectl get networkpolicies --all-namespaces -o wide > "$net_dir/networkpolicies.txt" 2>/dev/null || true
    kubectl get networkpolicies --all-namespaces -o yaml > "$net_dir/networkpolicies-yaml.yaml" 2>/dev/null || true
    
    # Ingress
    kubectl get ingress --all-namespaces -o wide > "$net_dir/ingress.txt" 2>/dev/null || true
    
    log_info "Network information collected"
}

# Generate summary report
generate_summary() {
    log_info "Generating summary report..."
    
    local summary_file="$OUTPUT_DIR/debug-summary.txt"
    
    cat > "$summary_file" << EOF
Kubernetes Cluster Debug Summary
================================
Generated: $(date)
Cluster: $(kubectl config current-context)

Node Status:
$(kubectl get nodes --no-headers | wc -l) total nodes
$(kubectl get nodes --no-headers | grep -c Ready || echo 0) ready nodes
$(kubectl get nodes --no-headers | grep -c NotReady || echo 0) not ready nodes

Pod Status:
$(kubectl get pods --all-namespaces --no-headers | wc -l) total pods
$(kubectl get pods --all-namespaces --no-headers | grep -c Running || echo 0) running pods
$(kubectl get pods --all-namespaces --no-headers | grep -c Pending || echo 0) pending pods
$(kubectl get pods --all-namespaces --no-headers | grep -c Failed || echo 0) failed pods

Gateway API Resources:
$(kubectl get gatewayclasses --no-headers 2>/dev/null | wc -l || echo 0) gateway classes
$(kubectl get gateways --all-namespaces --no-headers 2>/dev/null | wc -l || echo 0) gateways
$(kubectl get httproutes --all-namespaces --no-headers 2>/dev/null | wc -l || echo 0) http routes

Istio Resources:
$(kubectl get virtualservices --all-namespaces --no-headers 2>/dev/null | wc -l || echo 0) virtual services
$(kubectl get destinationrules --all-namespaces --no-headers 2>/dev/null | wc -l || echo 0) destination rules
$(kubectl get gateways.networking.istio.io --all-namespaces --no-headers 2>/dev/null | wc -l || echo 0) istio gateways

Recent Warning Events:
$(kubectl get events --all-namespaces --field-selector type=Warning --no-headers 2>/dev/null | tail -5 || echo "None")

Debug files location: $OUTPUT_DIR
EOF
    
    log_info "Summary report generated: $summary_file"
}

# Create archive
create_archive() {
    log_info "Creating debug archive..."
    
    local archive_name="debug-$(basename "$OUTPUT_DIR").tar.gz"
    local archive_path="$(dirname "$OUTPUT_DIR")/$archive_name"
    
    tar -czf "$archive_path" -C "$(dirname "$OUTPUT_DIR")" "$(basename "$OUTPUT_DIR")"
    
    log_info "Debug archive created: $archive_path"
    echo
    echo "=== Debug Collection Complete ==="
    echo "Archive: $archive_path"
    echo "Size: $(du -h "$archive_path" | cut -f1)"
    echo "================================="
}

# Main function
main() {
    log_info "Starting Kubernetes cluster debug collection..."
    
    setup_output_dir
    check_cluster_connectivity
    
    # Collect all information
    collect_node_info
    collect_namespace_info
    collect_gateway_api_info
    collect_istio_info
    collect_cert_info
    collect_monitoring_info
    collect_pod_info
    collect_events
    collect_logs
    collect_network_info
    
    # Generate summary and archive
    generate_summary
    create_archive
    
    log_info "Debug collection completed successfully!"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h          Show this help message"
        echo "  --no-logs          Skip log collection"
        echo "  --no-events        Skip event collection"
        echo "  --namespace NS     Focus on specific namespace"
        echo ""
        echo "Environment variables:"
        echo "  OUTPUT_DIR         Output directory (default: ./debug-output)"
        echo "  LOG_LINES          Number of log lines to collect (default: 1000)"
        echo "  INCLUDE_LOGS       Include pod logs (default: true)"
        echo "  INCLUDE_EVENTS     Include cluster events (default: true)"
        exit 0
        ;;
    --no-logs)
        INCLUDE_LOGS=false
        main
        ;;
    --no-events)
        INCLUDE_EVENTS=false
        main
        ;;
    --namespace)
        NAMESPACE="$2"
        main
        ;;
    "")
        main
        ;;
    *)
        log_error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac

