#!/bin/bash

# 🚀 Enterprise Gateway API & Service Mesh Platform Customization Script
# Interactive deployment and customization tool for multi-cloud infrastructure

set -euo pipefail

# Colors for enhanced UX
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly CONFIG_DIR="$PROJECT_ROOT/.platform-config"
readonly TEMPLATES_DIR="$SCRIPT_DIR/templates"

# Global variables
CLOUD_PROVIDER=""
CLUSTER_NAME=""
ENVIRONMENT=""
ENABLE_MONITORING=""
ENABLE_SECURITY=""
ENABLE_GITOPS=""
ENABLE_TRANSFORMATIONS=""
STORAGE_TYPE=""
NODE_COUNT=""
INSTANCE_TYPE=""

# Logging functions
log_header() {
    echo -e "\n${PURPLE}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${WHITE}  🚀 Enterprise Gateway API & Service Mesh Platform Setup      ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════════╝${NC}\n"
}

log_section() {
    echo -e "\n${CYAN}▶ $1${NC}"
    echo -e "${CYAN}$(printf '─%.0s' {1..60})${NC}"
}

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

log_prompt() {
    echo -e "${WHITE}[INPUT]${NC} $1"
}

# Utility functions
create_config_dir() {
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$TEMPLATES_DIR"
}

save_config() {
    cat > "$CONFIG_DIR/platform.conf" << EOF
# Platform Configuration Generated on $(date)
CLOUD_PROVIDER="$CLOUD_PROVIDER"
CLUSTER_NAME="$CLUSTER_NAME"
ENVIRONMENT="$ENVIRONMENT"
ENABLE_MONITORING="$ENABLE_MONITORING"
ENABLE_SECURITY="$ENABLE_SECURITY"
ENABLE_GITOPS="$ENABLE_GITOPS"
ENABLE_TRANSFORMATIONS="$ENABLE_TRANSFORMATIONS"
STORAGE_TYPE="$STORAGE_TYPE"
NODE_COUNT="$NODE_COUNT"
INSTANCE_TYPE="$INSTANCE_TYPE"
EOF
    log_success "Configuration saved to $CONFIG_DIR/platform.conf"
}

load_config() {
    if [[ -f "$CONFIG_DIR/platform.conf" ]]; then
        source "$CONFIG_DIR/platform.conf"
        log_info "Loaded existing configuration"
        return 0
    fi
    return 1
}

# Validation functions
validate_prerequisites() {
    log_section "🔍 Checking Prerequisites"
    
    local missing_tools=()
    local tools=("kubectl" "helm" "terraform" "git" "curl" "jq")
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        else
            log_success "$tool is installed"
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        echo -e "\n${YELLOW}Please install the missing tools and run this script again.${NC}"
        echo -e "${YELLOW}Installation guide: https://github.com/abdoElHodaky/Iacdash-/blob/main/QUICKSTART.md${NC}"
        exit 1
    fi
    
    log_success "All prerequisites satisfied!"
}

validate_cloud_credentials() {
    log_section "🔐 Validating Cloud Credentials"
    
    case "$CLOUD_PROVIDER" in
        "linode")
            if [[ -z "${LINODE_TOKEN:-}" ]]; then
                log_error "LINODE_TOKEN environment variable not set"
                log_info "Please set your Linode API token: export LINODE_TOKEN=your_token_here"
                return 1
            fi
            log_success "Linode credentials validated"
            ;;
        "gcp")
            if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
                log_error "GCP authentication not configured"
                log_info "Please run: gcloud auth login && gcloud auth application-default login"
                return 1
            fi
            log_success "GCP credentials validated"
            ;;
        "openstack")
            if [[ -z "${OS_AUTH_URL:-}" ]] || [[ -z "${OS_USERNAME:-}" ]]; then
                log_error "OpenStack credentials not configured"
                log_info "Please source your OpenStack RC file"
                return 1
            fi
            log_success "OpenStack credentials validated"
            ;;
        "kind")
            if ! docker info &> /dev/null; then
                log_error "Docker is not running (required for KinD)"
                log_info "Please start Docker and try again"
                return 1
            fi
            log_success "KinD prerequisites validated"
            ;;
    esac
}

# Interactive configuration functions
select_cloud_provider() {
    log_section "☁️ Cloud Provider Selection"
    
    echo -e "${WHITE}Available cloud providers:${NC}"
    echo -e "  ${GREEN}1)${NC} Linode LKE      - Managed Kubernetes with excellent price/performance"
    echo -e "  ${GREEN}2)${NC} Google GKE      - Advanced features, Gateway API native support"
    echo -e "  ${GREEN}3)${NC} OpenStack       - Private cloud, enterprise control"
    echo -e "  ${GREEN}4)${NC} KinD (Local)    - Development and testing environment"
    
    while true; do
        log_prompt "Select cloud provider (1-4): "
        read -r choice
        
        case "$choice" in
            1) CLOUD_PROVIDER="linode"; break ;;
            2) CLOUD_PROVIDER="gcp"; break ;;
            3) CLOUD_PROVIDER="openstack"; break ;;
            4) CLOUD_PROVIDER="kind"; break ;;
            *) log_warning "Invalid choice. Please select 1-4." ;;
        esac
    done
    
    log_success "Selected cloud provider: $CLOUD_PROVIDER"
}

configure_cluster() {
    log_section "🏗️ Cluster Configuration"
    
    # Cluster name
    log_prompt "Enter cluster name (default: gateway-${ENVIRONMENT}): "
    read -r cluster_input
    CLUSTER_NAME="${cluster_input:-gateway-${ENVIRONMENT}}"
    
    # Node configuration based on cloud provider
    case "$CLOUD_PROVIDER" in
        "linode"|"gcp"|"openstack")
            echo -e "\n${WHITE}Node pool configuration:${NC}"
            log_prompt "Number of nodes (default: 3): "
            read -r node_input
            NODE_COUNT="${node_input:-3}"
            
            case "$CLOUD_PROVIDER" in
                "linode")
                    echo -e "${WHITE}Available instance types:${NC}"
                    echo -e "  ${GREEN}1)${NC} g6-standard-2  (2 vCPU, 4GB RAM) - Development"
                    echo -e "  ${GREEN}2)${NC} g6-standard-4  (4 vCPU, 8GB RAM) - Production"
                    echo -e "  ${GREEN}3)${NC} g6-standard-8  (8 vCPU, 16GB RAM) - High Performance"
                    
                    while true; do
                        log_prompt "Select instance type (1-3): "
                        read -r instance_choice
                        case "$instance_choice" in
                            1) INSTANCE_TYPE="g6-standard-2"; break ;;
                            2) INSTANCE_TYPE="g6-standard-4"; break ;;
                            3) INSTANCE_TYPE="g6-standard-8"; break ;;
                            *) log_warning "Invalid choice. Please select 1-3." ;;
                        esac
                    done
                    ;;
                "gcp")
                    echo -e "${WHITE}Available machine types:${NC}"
                    echo -e "  ${GREEN}1)${NC} e2-standard-2  (2 vCPU, 8GB RAM) - Development"
                    echo -e "  ${GREEN}2)${NC} e2-standard-4  (4 vCPU, 16GB RAM) - Production"
                    echo -e "  ${GREEN}3)${NC} e2-standard-8  (8 vCPU, 32GB RAM) - High Performance"
                    
                    while true; do
                        log_prompt "Select machine type (1-3): "
                        read -r machine_choice
                        case "$machine_choice" in
                            1) INSTANCE_TYPE="e2-standard-2"; break ;;
                            2) INSTANCE_TYPE="e2-standard-4"; break ;;
                            3) INSTANCE_TYPE="e2-standard-8"; break ;;
                            *) log_warning "Invalid choice. Please select 1-3." ;;
                        esac
                    done
                    ;;
                "openstack")
                    log_prompt "Enter flavor name (e.g., m1.medium): "
                    read -r INSTANCE_TYPE
                    ;;
            esac
            ;;
        "kind")
            NODE_COUNT="1"
            INSTANCE_TYPE="local"
            log_info "KinD cluster will use local Docker containers"
            ;;
    esac
    
    log_success "Cluster configuration: $CLUSTER_NAME ($NODE_COUNT nodes, $INSTANCE_TYPE)"
}

select_environment() {
    log_section "🌍 Environment Selection"
    
    echo -e "${WHITE}Available environments:${NC}"
    echo -e "  ${GREEN}1)${NC} development - Full features, relaxed security, detailed logging"
    echo -e "  ${GREEN}2)${NC} staging     - Production-like, testing optimized"
    echo -e "  ${GREEN}3)${NC} production  - High availability, strict security, optimized performance"
    
    while true; do
        log_prompt "Select environment (1-3): "
        read -r env_choice
        
        case "$env_choice" in
            1) ENVIRONMENT="development"; break ;;
            2) ENVIRONMENT="staging"; break ;;
            3) ENVIRONMENT="production"; break ;;
            *) log_warning "Invalid choice. Please select 1-3." ;;
        esac
    done
    
    log_success "Selected environment: $ENVIRONMENT"
}

configure_features() {
    log_section "🔧 Feature Configuration"
    
    # Monitoring
    echo -e "\n${WHITE}📊 Observability Stack (Prometheus, Grafana, Loki, Tempo):${NC}"
    echo -e "  Provides comprehensive metrics, logging, and distributed tracing"
    while true; do
        log_prompt "Enable monitoring stack? (y/n): "
        read -r monitoring_choice
        case "$monitoring_choice" in
            [Yy]*) ENABLE_MONITORING="true"; break ;;
            [Nn]*) ENABLE_MONITORING="false"; break ;;
            *) log_warning "Please answer y or n." ;;
        esac
    done
    
    # Security
    echo -e "\n${WHITE}🔒 Security Features (mTLS, Certificates, Network Policies):${NC}"
    echo -e "  Enables zero-trust security with automatic certificate management"
    while true; do
        log_prompt "Enable advanced security? (y/n): "
        read -r security_choice
        case "$security_choice" in
            [Yy]*) ENABLE_SECURITY="true"; break ;;
            [Nn]*) ENABLE_SECURITY="false"; break ;;
            *) log_warning "Please answer y or n." ;;
        esac
    done
    
    # GitOps
    echo -e "\n${WHITE}🤖 GitOps Automation (FluxCD, Progressive Delivery):${NC}"
    echo -e "  Automated deployments with canary releases and rollback capabilities"
    while true; do
        log_prompt "Enable GitOps automation? (y/n): "
        read -r gitops_choice
        case "$gitops_choice" in
            [Yy]*) ENABLE_GITOPS="true"; break ;;
            [Nn]*) ENABLE_GITOPS="false"; break ;;
            *) log_warning "Please answer y or n." ;;
        esac
    done
    
    # Transformations
    echo -e "\n${WHITE}🔄 Advanced Transformations (WASM, OPA, Envoy Filters):${NC}"
    echo -e "  Custom request/response processing with policy enforcement"
    while true; do
        log_prompt "Enable transformations? (y/n): "
        read -r transform_choice
        case "$transform_choice" in
            [Yy]*) ENABLE_TRANSFORMATIONS="true"; break ;;
            [Nn]*) ENABLE_TRANSFORMATIONS="false"; break ;;
            *) log_warning "Please answer y or n." ;;
        esac
    done
    
    # Storage
    echo -e "\n${WHITE}💾 Storage Configuration:${NC}"
    echo -e "  ${GREEN}1)${NC} basic     - Standard persistent volumes"
    echo -e "  ${GREEN}2)${NC} advanced  - High-performance SSD with backup"
    echo -e "  ${GREEN}3)${NC} minimal   - No persistent storage (stateless only)"
    
    while true; do
        log_prompt "Select storage type (1-3): "
        read -r storage_choice
        case "$storage_choice" in
            1) STORAGE_TYPE="basic"; break ;;
            2) STORAGE_TYPE="advanced"; break ;;
            3) STORAGE_TYPE="minimal"; break ;;
            *) log_warning "Invalid choice. Please select 1-3." ;;
        esac
    done
    
    log_success "Feature configuration completed"
}

generate_terraform_config() {
    log_section "📝 Generating Terraform Configuration"
    
    local tf_dir="$CONFIG_DIR/terraform"
    mkdir -p "$tf_dir"
    
    # Generate main.tf based on cloud provider
    case "$CLOUD_PROVIDER" in
        "linode")
            cat > "$tf_dir/main.tf" << EOF
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 2.9"
    }
  }
}

provider "linode" {
  token = var.linode_token
}

module "linode_cluster" {
  source = "../../terraform/modules/linode-lke"
  
  cluster_name       = "$CLUSTER_NAME"
  region            = var.region
  kubernetes_version = var.kubernetes_version
  
  node_pools = [
    {
      type  = "$INSTANCE_TYPE"
      count = $NODE_COUNT
      autoscaler = {
        min = $NODE_COUNT
        max = $(($NODE_COUNT * 2))
      }
    }
  ]
  
  tags = [
    "environment:$ENVIRONMENT",
    "managed-by:terraform",
    "platform:gateway-api"
  ]
}
EOF
            ;;
        "gcp")
            cat > "$tf_dir/main.tf" << EOF
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

module "gke_cluster" {
  source = "../../terraform/modules/gke-cluster"
  
  cluster_name       = "$CLUSTER_NAME"
  project_id        = var.project_id
  location          = var.region
  kubernetes_version = var.kubernetes_version
  
  node_pools = [
    {
      name         = "primary"
      machine_type = "$INSTANCE_TYPE"
      min_count    = $NODE_COUNT
      max_count    = $(($NODE_COUNT * 2))
      disk_size_gb = 50
    }
  ]
  
  labels = {
    environment = "$ENVIRONMENT"
    managed-by  = "terraform"
    platform    = "gateway-api"
  }
}
EOF
            ;;
        "kind")
            cat > "$tf_dir/main.tf" << EOF
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.2"
    }
  }
}

module "kind_cluster" {
  source = "../../terraform/modules/kind-cluster"
  
  cluster_name = "$CLUSTER_NAME"
  
  node_image = "kindest/node:v1.28.0"
  
  extra_port_mappings = [
    {
      container_port = 80
      host_port      = 80
    },
    {
      container_port = 443
      host_port      = 443
    }
  ]
}
EOF
            ;;
    esac
    
    # Generate variables.tf
    cat > "$tf_dir/variables.tf" << EOF
variable "region" {
  description = "Cloud provider region"
  type        = string
  default     = "us-east-1"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
}
EOF
    
    case "$CLOUD_PROVIDER" in
        "linode")
            cat >> "$tf_dir/variables.tf" << EOF

variable "linode_token" {
  description = "Linode API token"
  type        = string
  sensitive   = true
}
EOF
            ;;
        "gcp")
            cat >> "$tf_dir/variables.tf" << EOF

variable "project_id" {
  description = "GCP project ID"
  type        = string
}
EOF
            ;;
    esac
    
    # Generate terraform.tfvars.example
    cat > "$tf_dir/terraform.tfvars.example" << EOF
# Copy this file to terraform.tfvars and fill in your values

region             = "us-east-1"
kubernetes_version = "1.28"
EOF
    
    case "$CLOUD_PROVIDER" in
        "linode")
            cat >> "$tf_dir/terraform.tfvars.example" << EOF
linode_token = "your-linode-api-token"
EOF
            ;;
        "gcp")
            cat >> "$tf_dir/terraform.tfvars.example" << EOF
project_id = "your-gcp-project-id"
EOF
            ;;
    esac
    
    log_success "Terraform configuration generated in $tf_dir"
}

generate_deployment_script() {
    log_section "🚀 Generating Deployment Script"
    
    cat > "$CONFIG_DIR/deploy.sh" << 'EOF'
#!/bin/bash

# Auto-generated deployment script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Load configuration
source "$SCRIPT_DIR/platform.conf"

log_info() {
    echo -e "\033[0;34m[INFO]\033[0m $1"
}

log_success() {
    echo -e "\033[0;32m[SUCCESS]\033[0m $1"
}

log_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1"
}

# Deploy infrastructure
deploy_infrastructure() {
    log_info "Deploying infrastructure..."
    
    cd "$SCRIPT_DIR/terraform"
    
    if [[ ! -f "terraform.tfvars" ]]; then
        log_error "terraform.tfvars not found. Please copy from terraform.tfvars.example and configure."
        exit 1
    fi
    
    terraform init
    terraform plan
    terraform apply -auto-approve
    
    log_success "Infrastructure deployed successfully"
}

# Configure kubectl
configure_kubectl() {
    log_info "Configuring kubectl..."
    
    case "$CLOUD_PROVIDER" in
        "linode")
            terraform output -raw kubeconfig > ~/.kube/config-$CLUSTER_NAME
            export KUBECONFIG=~/.kube/config-$CLUSTER_NAME
            ;;
        "gcp")
            gcloud container clusters get-credentials $CLUSTER_NAME --region=$(terraform output -raw region)
            ;;
        "kind")
            kind export kubeconfig --name $CLUSTER_NAME
            ;;
    esac
    
    kubectl cluster-info
    log_success "kubectl configured successfully"
}

# Install platform components
install_platform() {
    log_info "Installing platform components..."
    
    cd "$PROJECT_ROOT"
    
    # Install Gateway API CRDs
    kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml
    
    # Install Istio if service mesh is enabled
    if [[ "$ENABLE_SECURITY" == "true" ]]; then
        log_info "Installing Istio service mesh..."
        curl -L https://istio.io/downloadIstio | sh -
        istio-*/bin/istioctl install --set values.defaultRevision=default -y
        kubectl label namespace default istio-injection=enabled
    fi
    
    # Install monitoring stack
    if [[ "$ENABLE_MONITORING" == "true" ]]; then
        log_info "Installing monitoring stack..."
        helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
        helm repo add grafana https://grafana.github.io/helm-charts
        helm repo update
        
        kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
        helm upgrade --install prometheus prometheus-community/kube-prometheus-stack -n monitoring
    fi
    
    # Install FluxCD if GitOps is enabled
    if [[ "$ENABLE_GITOPS" == "true" ]]; then
        log_info "Installing FluxCD..."
        flux install
        kubectl apply -f flux/clusters/$ENVIRONMENT/
    fi
    
    log_success "Platform components installed successfully"
}

# Main deployment flow
main() {
    echo "🚀 Starting deployment for $ENVIRONMENT environment on $CLOUD_PROVIDER"
    
    deploy_infrastructure
    configure_kubectl
    install_platform
    
    echo "✅ Deployment completed successfully!"
    echo "📊 Access your cluster: kubectl get nodes"
    
    if [[ "$ENABLE_MONITORING" == "true" ]]; then
        echo "📈 Grafana: kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
    fi
}

main "$@"
EOF
    
    chmod +x "$CONFIG_DIR/deploy.sh"
    log_success "Deployment script generated: $CONFIG_DIR/deploy.sh"
}

display_summary() {
    log_section "📋 Configuration Summary"
    
    echo -e "${WHITE}Platform Configuration:${NC}"
    echo -e "  ${CYAN}Cloud Provider:${NC}     $CLOUD_PROVIDER"
    echo -e "  ${CYAN}Environment:${NC}        $ENVIRONMENT"
    echo -e "  ${CYAN}Cluster Name:${NC}       $CLUSTER_NAME"
    echo -e "  ${CYAN}Node Count:${NC}         $NODE_COUNT"
    echo -e "  ${CYAN}Instance Type:${NC}      $INSTANCE_TYPE"
    echo -e "  ${CYAN}Storage Type:${NC}       $STORAGE_TYPE"
    
    echo -e "\n${WHITE}Enabled Features:${NC}"
    echo -e "  ${CYAN}Monitoring:${NC}         $([[ "$ENABLE_MONITORING" == "true" ]] && echo "✅ Enabled" || echo "❌ Disabled")"
    echo -e "  ${CYAN}Security:${NC}           $([[ "$ENABLE_SECURITY" == "true" ]] && echo "✅ Enabled" || echo "❌ Disabled")"
    echo -e "  ${CYAN}GitOps:${NC}             $([[ "$ENABLE_GITOPS" == "true" ]] && echo "✅ Enabled" || echo "❌ Disabled")"
    echo -e "  ${CYAN}Transformations:${NC}    $([[ "$ENABLE_TRANSFORMATIONS" == "true" ]] && echo "✅ Enabled" || echo "❌ Disabled")"
    
    echo -e "\n${WHITE}Generated Files:${NC}"
    echo -e "  ${CYAN}Configuration:${NC}      $CONFIG_DIR/platform.conf"
    echo -e "  ${CYAN}Terraform:${NC}          $CONFIG_DIR/terraform/"
    echo -e "  ${CYAN}Deploy Script:${NC}      $CONFIG_DIR/deploy.sh"
    
    echo -e "\n${GREEN}Next Steps:${NC}"
    echo -e "  1. Review configuration: ${YELLOW}cat $CONFIG_DIR/platform.conf${NC}"
    echo -e "  2. Configure credentials: ${YELLOW}cp $CONFIG_DIR/terraform/terraform.tfvars.example $CONFIG_DIR/terraform/terraform.tfvars${NC}"
    echo -e "  3. Edit terraform.tfvars with your credentials"
    echo -e "  4. Deploy platform: ${YELLOW}$CONFIG_DIR/deploy.sh${NC}"
    
    echo -e "\n${PURPLE}🎉 Platform customization completed successfully!${NC}"
}

# Main execution flow
main() {
    log_header
    
    # Check if we should load existing config
    if [[ "${1:-}" == "--load-config" ]] && load_config; then
        log_info "Using existing configuration. Use --reconfigure to start fresh."
    else
        validate_prerequisites
        create_config_dir
        
        select_cloud_provider
        select_environment
        configure_cluster
        configure_features
        
        save_config
    fi
    
    validate_cloud_credentials
    generate_terraform_config
    generate_deployment_script
    display_summary
}

# Handle command line arguments
case "${1:-}" in
    "--help"|"-h")
        echo "🚀 Enterprise Gateway API & Service Mesh Platform Customization"
        echo ""
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --help, -h           Show this help message"
        echo "  --load-config        Load existing configuration"
        echo "  --reconfigure        Force reconfiguration"
        echo ""
        echo "This interactive script helps you customize and deploy the platform"
        echo "across multiple cloud providers with your preferred configuration."
        exit 0
        ;;
    "--reconfigure")
        rm -rf "$CONFIG_DIR"
        main
        ;;
    *)
        main "$@"
        ;;
esac
