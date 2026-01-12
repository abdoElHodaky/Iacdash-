#!/bin/bash
set -euo pipefail

# Kubernetes Cluster Backup Script
# Backs up etcd, persistent volumes, and cluster configuration

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/backup/kubernetes}"
CLUSTER_NAME="${CLUSTER_NAME:-gateway-mesh}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
S3_BUCKET="${S3_BUCKET:-}"
VELERO_NAMESPACE="${VELERO_NAMESPACE:-velero}"
ETCD_NAMESPACE="${ETCD_NAMESPACE:-kube-system}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check Velero (optional)
    if kubectl get namespace "$VELERO_NAMESPACE" &> /dev/null; then
        VELERO_AVAILABLE=true
        log_info "Velero is available for backup"
    else
        VELERO_AVAILABLE=false
        log_warn "Velero is not installed, skipping PV backups"
    fi
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    log_info "Prerequisites check completed"
}

# Backup etcd
backup_etcd() {
    log_info "Starting etcd backup..."
    
    local backup_file="$BACKUP_DIR/etcd-backup-$(date +%Y%m%d-%H%M%S).db"
    
    # For managed clusters (EKS, GKE, AKS), etcd backup is handled by the cloud provider
    if kubectl get nodes -o jsonpath='{.items[0].spec.providerID}' | grep -E "(aws|gce|azure)" &> /dev/null; then
        log_warn "Managed cluster detected, etcd backup is handled by cloud provider"
        return 0
    fi
    
    # For self-managed clusters, backup etcd directly
    local etcd_pod=$(kubectl get pods -n "$ETCD_NAMESPACE" -l component=etcd -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$etcd_pod" ]]; then
        log_info "Backing up etcd from pod: $etcd_pod"
        kubectl exec -n "$ETCD_NAMESPACE" "$etcd_pod" -- etcdctl \
            --endpoints=https://127.0.0.1:2379 \
            --cacert=/etc/kubernetes/pki/etcd/ca.crt \
            --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
            --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
            snapshot save /tmp/etcd-backup.db
        
        kubectl cp "$ETCD_NAMESPACE/$etcd_pod:/tmp/etcd-backup.db" "$backup_file"
        log_info "etcd backup saved to: $backup_file"
    else
        log_warn "etcd pod not found, skipping etcd backup"
    fi
}

# Backup cluster configuration
backup_cluster_config() {
    log_info "Starting cluster configuration backup..."
    
    local config_dir="$BACKUP_DIR/cluster-config-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$config_dir"
    
    # Backup all namespaces
    log_info "Backing up namespaces..."
    kubectl get namespaces -o yaml > "$config_dir/namespaces.yaml"
    
    # Backup cluster-wide resources
    log_info "Backing up cluster-wide resources..."
    kubectl get clusterroles -o yaml > "$config_dir/clusterroles.yaml"
    kubectl get clusterrolebindings -o yaml > "$config_dir/clusterrolebindings.yaml"
    kubectl get customresourcedefinitions -o yaml > "$config_dir/crds.yaml"
    kubectl get persistentvolumes -o yaml > "$config_dir/persistent-volumes.yaml"
    kubectl get storageclasses -o yaml > "$config_dir/storage-classes.yaml"
    
    # Backup important namespaced resources
    for ns in kube-system flux-system istio-system monitoring cert-manager external-secrets-system; do
        if kubectl get namespace "$ns" &> /dev/null; then
            log_info "Backing up namespace: $ns"
            local ns_dir="$config_dir/namespaces/$ns"
            mkdir -p "$ns_dir"
            
            # Get all resources in namespace
            kubectl get all -n "$ns" -o yaml > "$ns_dir/all-resources.yaml" 2>/dev/null || true
            kubectl get configmaps -n "$ns" -o yaml > "$ns_dir/configmaps.yaml" 2>/dev/null || true
            kubectl get secrets -n "$ns" -o yaml > "$ns_dir/secrets.yaml" 2>/dev/null || true
            kubectl get pvc -n "$ns" -o yaml > "$ns_dir/persistent-volume-claims.yaml" 2>/dev/null || true
        fi
    done
    
    # Backup Helm releases
    if command -v helm &> /dev/null; then
        log_info "Backing up Helm releases..."
        helm list --all-namespaces -o yaml > "$config_dir/helm-releases.yaml" 2>/dev/null || true
    fi
    
    # Create archive
    tar -czf "$config_dir.tar.gz" -C "$BACKUP_DIR" "$(basename "$config_dir")"
    rm -rf "$config_dir"
    
    log_info "Cluster configuration backup saved to: $config_dir.tar.gz"
}

# Backup persistent volumes using Velero
backup_persistent_volumes() {
    if [[ "$VELERO_AVAILABLE" != "true" ]]; then
        log_warn "Velero not available, skipping PV backup"
        return 0
    fi
    
    log_info "Starting persistent volume backup with Velero..."
    
    local backup_name="$CLUSTER_NAME-pv-backup-$(date +%Y%m%d-%H%M%S)"
    
    # Create Velero backup
    kubectl create -f - <<EOF
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: $backup_name
  namespace: $VELERO_NAMESPACE
spec:
  includedNamespaces:
  - "*"
  storageLocation: default
  volumeSnapshotLocations:
  - default
  ttl: ${RETENTION_DAYS}d
EOF
    
    # Wait for backup to complete
    log_info "Waiting for Velero backup to complete..."
    kubectl wait --for=condition=Completed backup/"$backup_name" -n "$VELERO_NAMESPACE" --timeout=1800s
    
    # Check backup status
    local status=$(kubectl get backup "$backup_name" -n "$VELERO_NAMESPACE" -o jsonpath='{.status.phase}')
    if [[ "$status" == "Completed" ]]; then
        log_info "Velero backup completed successfully: $backup_name"
    else
        log_error "Velero backup failed with status: $status"
        return 1
    fi
}

# Upload to S3 (optional)
upload_to_s3() {
    if [[ -z "$S3_BUCKET" ]]; then
        log_info "S3_BUCKET not configured, skipping upload"
        return 0
    fi
    
    if ! command -v aws &> /dev/null; then
        log_warn "AWS CLI not installed, skipping S3 upload"
        return 0
    fi
    
    log_info "Uploading backups to S3 bucket: $S3_BUCKET"
    
    local s3_path="s3://$S3_BUCKET/kubernetes-backups/$CLUSTER_NAME/$(date +%Y/%m/%d)"
    
    # Upload all backup files
    aws s3 sync "$BACKUP_DIR" "$s3_path" --exclude "*" --include "*.db" --include "*.tar.gz"
    
    log_info "Backup upload to S3 completed"
}

# Cleanup old backups
cleanup_old_backups() {
    log_info "Cleaning up backups older than $RETENTION_DAYS days..."
    
    # Local cleanup
    find "$BACKUP_DIR" -type f \( -name "*.db" -o -name "*.tar.gz" \) -mtime +$RETENTION_DAYS -delete
    
    # S3 cleanup (if configured)
    if [[ -n "$S3_BUCKET" ]] && command -v aws &> /dev/null; then
        aws s3api list-objects-v2 --bucket "$S3_BUCKET" --prefix "kubernetes-backups/$CLUSTER_NAME/" \
            --query "Contents[?LastModified<='$(date -d "$RETENTION_DAYS days ago" --iso-8601)'].Key" \
            --output text | xargs -r -I {} aws s3 rm "s3://$S3_BUCKET/{}"
    fi
    
    log_info "Cleanup completed"
}

# Main backup function
main() {
    log_info "Starting Kubernetes cluster backup for: $CLUSTER_NAME"
    log_info "Backup directory: $BACKUP_DIR"
    log_info "Retention period: $RETENTION_DAYS days"
    
    check_prerequisites
    
    # Run backup operations
    backup_etcd
    backup_cluster_config
    backup_persistent_volumes
    
    # Upload and cleanup
    upload_to_s3
    cleanup_old_backups
    
    log_info "Backup completed successfully!"
    
    # Print backup summary
    echo
    echo "=== Backup Summary ==="
    echo "Cluster: $CLUSTER_NAME"
    echo "Date: $(date)"
    echo "Backup location: $BACKUP_DIR"
    if [[ -n "$S3_BUCKET" ]]; then
        echo "S3 location: s3://$S3_BUCKET/kubernetes-backups/$CLUSTER_NAME/"
    fi
    echo "======================="
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h          Show this help message"
        echo "  --dry-run          Show what would be backed up without doing it"
        echo ""
        echo "Environment variables:"
        echo "  BACKUP_DIR         Backup directory (default: /backup/kubernetes)"
        echo "  CLUSTER_NAME       Cluster name (default: gateway-mesh)"
        echo "  RETENTION_DAYS     Backup retention in days (default: 30)"
        echo "  S3_BUCKET          S3 bucket for backup storage (optional)"
        echo "  VELERO_NAMESPACE   Velero namespace (default: velero)"
        exit 0
        ;;
    --dry-run)
        log_info "DRY RUN MODE - No actual backups will be created"
        check_prerequisites
        log_info "Would backup etcd, cluster config, and persistent volumes"
        log_info "Would upload to S3: ${S3_BUCKET:-not configured}"
        log_info "Would cleanup backups older than $RETENTION_DAYS days"
        exit 0
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

