terraform {
  required_version = ">= 1.6.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.53"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# Data source to find the cluster template
data "openstack_containerinfra_clustertemplate_v1" "template" {
  name = var.cluster_template_name
}

# Data source for keypair validation
data "openstack_compute_keypair_v2" "keypair" {
  name = var.keypair_name
}

# Create the Kubernetes cluster using Magnum
resource "openstack_containerinfra_cluster_v1" "cluster" {
  name                = var.cluster_name
  cluster_template_id = data.openstack_containerinfra_clustertemplate_v1.template.id
  
  # Node configuration
  master_count = var.master_count
  node_count   = var.node_count
  
  # SSH access
  keypair = data.openstack_compute_keypair_v2.keypair.name
  
  # Cluster labels for configuration
  labels = merge(
    {
      # Kubernetes version
      kube_tag = var.kubernetes_version
      
      # Load balancer configuration
      master_lb_enabled = "true"
      
      # Auto-scaling configuration
      auto_scaling_enabled = var.auto_scaling_enabled ? "true" : "false"
      min_node_count      = tostring(var.min_node_count)
      max_node_count      = tostring(var.max_node_count)
      
      # Cloud provider configuration
      cloud_provider_tag = var.kubernetes_version
      
      # Heat container agent
      heat_container_agent_tag = var.heat_container_agent_tag
      
      # Docker configuration
      docker_storage_driver = var.docker_storage_driver
      docker_volume_size    = tostring(var.docker_volume_size)
      
      # Network configuration
      flannel_network_cidr    = var.flannel_network_cidr
      flannel_network_subnets = var.flannel_network_subnets
      flannel_backend         = var.flannel_backend
      
      # Monitoring and logging
      monitoring_enabled = var.monitoring_enabled ? "true" : "false"
      logging_enabled    = var.logging_enabled ? "true" : "false"
      
      # Security
      tls_disabled = "false"
      
      # Additional features
      ingress_controller = var.ingress_controller
      dashboard_enabled  = var.dashboard_enabled ? "true" : "false"
    },
    var.additional_labels
  )
  
  # Merge labels with existing ones
  merge_labels = true
  
  # Timeouts for cluster operations
  timeouts {
    create = var.create_timeout
    update = var.update_timeout
    delete = var.delete_timeout
  }
  
  # Tags for resource management
  tags = var.tags
}

# Wait for cluster to be ready before proceeding
resource "null_resource" "wait_for_cluster" {
  depends_on = [openstack_containerinfra_cluster_v1.cluster]
  
  provisioner "local-exec" {
    command = "sleep ${var.cluster_ready_wait_time}"
  }
  
  triggers = {
    cluster_id = openstack_containerinfra_cluster_v1.cluster.id
  }
}

# Get cluster data after it's ready
data "openstack_containerinfra_cluster_v1" "cluster_data" {
  name       = openstack_containerinfra_cluster_v1.cluster.name
  depends_on = [null_resource.wait_for_cluster]
}

# Save kubeconfig to local file
resource "local_file" "kubeconfig" {
  content    = data.openstack_containerinfra_cluster_v1.cluster_data.kubeconfig.raw_config
  filename   = "${var.kubeconfig_path}/${var.cluster_name}-kubeconfig"
  depends_on = [data.openstack_containerinfra_cluster_v1.cluster_data]
  
  # Set appropriate file permissions
  file_permission = "0600"
}

# Optional: Create cluster admin service account
resource "null_resource" "create_admin_sa" {
  count = var.create_admin_service_account ? 1 : 0
  
  depends_on = [local_file.kubeconfig]
  
  provisioner "local-exec" {
    command = <<-EOT
      export KUBECONFIG=${local_file.kubeconfig.filename}
      
      # Wait for cluster to be fully ready
      kubectl wait --for=condition=Ready nodes --all --timeout=300s
      
      # Create admin service account
      kubectl create serviceaccount cluster-admin-sa -n kube-system --dry-run=client -o yaml | kubectl apply -f -
      
      # Bind to cluster-admin role
      kubectl create clusterrolebinding cluster-admin-sa-binding \
        --clusterrole=cluster-admin \
        --serviceaccount=kube-system:cluster-admin-sa \
        --dry-run=client -o yaml | kubectl apply -f -
    EOT
  }
  
  triggers = {
    kubeconfig_content = local_file.kubeconfig.content
  }
}

# Optional: Install basic monitoring if enabled
resource "null_resource" "install_monitoring" {
  count = var.install_monitoring ? 1 : 0
  
  depends_on = [null_resource.create_admin_sa]
  
  provisioner "local-exec" {
    command = <<-EOT
      export KUBECONFIG=${local_file.kubeconfig.filename}
      
      # Add Prometheus Helm repository
      helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
      helm repo update
      
      # Install kube-prometheus-stack
      helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --create-namespace \
        --set prometheus.prometheusSpec.retention=30d \
        --set grafana.adminPassword=${var.grafana_admin_password} \
        --wait
    EOT
  }
  
  triggers = {
    monitoring_enabled = var.install_monitoring
  }
}

