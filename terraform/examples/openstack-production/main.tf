# OpenStack Production Cluster Example
# This example demonstrates how to deploy a production-ready Kubernetes cluster on OpenStack

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.53"
    }
  }
}

# Configure OpenStack provider
# Credentials should be provided via environment variables or openrc.sh
provider "openstack" {
  # auth_url    = var.auth_url
  # tenant_name = var.tenant_name
  # user_name   = var.user_name
  # password    = var.password
  # region      = var.region
}

# Production cluster with high availability
module "production_cluster" {
  source = "../../modules/openstack-cluster"
  
  # Cluster configuration
  cluster_name         = var.cluster_name
  cluster_template_name = var.cluster_template_name
  kubernetes_version   = var.kubernetes_version
  environment         = "production"
  
  # High availability configuration
  master_count = 3  # HA masters
  node_count   = 5  # Initial worker nodes
  
  # Auto-scaling for production workloads
  auto_scaling_enabled = true
  min_node_count      = 5
  max_node_count      = 20
  
  # SSH access
  keypair_name = var.keypair_name
  
  # Network configuration for production
  flannel_network_cidr    = "10.200.0.0/16"
  flannel_network_subnets = "10.200.0.0/24"
  flannel_backend         = "vxlan"
  
  # Storage configuration
  docker_storage_driver = "overlay2"
  docker_volume_size    = 50  # Larger volumes for production
  
  # Enable production features
  monitoring_enabled = true
  logging_enabled    = true
  dashboard_enabled  = false  # Disable for security
  ingress_controller = "istio"
  
  # Production timeouts
  create_timeout = "90m"  # Longer timeout for production
  update_timeout = "90m"
  delete_timeout = "45m"
  
  # Kubeconfig location
  kubeconfig_path = var.kubeconfig_path
  
  # Optional monitoring installation
  install_monitoring     = var.install_monitoring
  grafana_admin_password = var.grafana_admin_password
  
  # Production labels
  additional_labels = {
    environment     = "production"
    project         = var.project_name
    cost_center     = var.cost_center
    backup_policy   = "daily"
    monitoring      = "enabled"
    security_scan   = "enabled"
  }
  
  # Resource tags
  tags = [
    "production",
    "kubernetes",
    "gateway-api",
    "service-mesh",
    "istio",
    var.project_name
  ]
}

# Optional: Create additional resources for production

# Network security group for cluster nodes
resource "openstack_networking_secgroup_v2" "cluster_security_group" {
  name        = "${var.cluster_name}-security-group"
  description = "Security group for ${var.cluster_name} cluster nodes"
  
  tags = [
    "kubernetes",
    "production",
    var.project_name
  ]
}

# Allow SSH access
resource "openstack_networking_secgroup_rule_v2" "ssh_access" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.ssh_allowed_cidr
  security_group_id = openstack_networking_secgroup_v2.cluster_security_group.id
}

# Allow Kubernetes API access
resource "openstack_networking_secgroup_rule_v2" "k8s_api_access" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = var.api_allowed_cidr
  security_group_id = openstack_networking_secgroup_v2.cluster_security_group.id
}

# Allow HTTP/HTTPS traffic for ingress
resource "openstack_networking_secgroup_rule_v2" "http_access" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.cluster_security_group.id
}

resource "openstack_networking_secgroup_rule_v2" "https_access" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.cluster_security_group.id
}

# Optional: Create persistent volumes for applications
resource "openstack_blockstorage_volume_v3" "app_storage" {
  count = var.create_app_storage ? var.app_storage_count : 0
  
  name        = "${var.cluster_name}-app-storage-${count.index + 1}"
  description = "Persistent storage for applications in ${var.cluster_name}"
  size        = var.app_storage_size
  volume_type = var.app_storage_type
  
  metadata = {
    cluster     = var.cluster_name
    environment = "production"
    project     = var.project_name
  }
}

# Local file for cluster connection script
resource "local_file" "connect_script" {
  filename = "${var.kubeconfig_path}/connect-${var.cluster_name}.sh"
  content = templatefile("${path.module}/templates/connect.sh.tpl", {
    cluster_name    = var.cluster_name
    kubeconfig_path = module.production_cluster.kubeconfig_path
    api_address     = module.production_cluster.api_address
  })
  file_permission = "0755"
}

# Local file for cluster info
resource "local_file" "cluster_info" {
  filename = "${var.kubeconfig_path}/${var.cluster_name}-info.json"
  content = jsonencode({
    cluster_name      = module.production_cluster.cluster_name
    cluster_id        = module.production_cluster.cluster_id
    api_address       = module.production_cluster.api_address
    kubernetes_version = module.production_cluster.kubernetes_version
    master_count      = module.production_cluster.master_count
    node_count        = module.production_cluster.node_count
    environment       = "production"
    created_at        = timestamp()
  })
}

