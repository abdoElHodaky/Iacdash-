# Cluster Information
output "cluster_id" {
  description = "The ID of the created cluster"
  value       = openstack_containerinfra_cluster_v1.cluster.id
}

output "cluster_name" {
  description = "The name of the created cluster"
  value       = openstack_containerinfra_cluster_v1.cluster.name
}

output "cluster_uuid" {
  description = "The UUID of the created cluster"
  value       = openstack_containerinfra_cluster_v1.cluster.uuid
}

output "cluster_status" {
  description = "The status of the cluster"
  value       = openstack_containerinfra_cluster_v1.cluster.status
}

# API Access
output "api_address" {
  description = "The API server address of the cluster"
  value       = openstack_containerinfra_cluster_v1.cluster.api_address
  sensitive   = true
}

output "master_addresses" {
  description = "List of master node addresses"
  value       = openstack_containerinfra_cluster_v1.cluster.master_addresses
  sensitive   = true
}

output "node_addresses" {
  description = "List of worker node addresses"
  value       = openstack_containerinfra_cluster_v1.cluster.node_addresses
  sensitive   = true
}

# Kubeconfig
output "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  value       = local_file.kubeconfig.filename
}

output "kubeconfig_content" {
  description = "Content of the kubeconfig file"
  value       = local_file.kubeconfig.content
  sensitive   = true
}

# Cluster Configuration
output "cluster_template_id" {
  description = "The cluster template ID used"
  value       = data.openstack_containerinfra_clustertemplate_v1.template.id
}

output "master_count" {
  description = "Number of master nodes"
  value       = openstack_containerinfra_cluster_v1.cluster.master_count
}

output "node_count" {
  description = "Number of worker nodes"
  value       = openstack_containerinfra_cluster_v1.cluster.node_count
}

# Network Information
output "cluster_network_cidr" {
  description = "The cluster network CIDR"
  value       = try(openstack_containerinfra_cluster_v1.cluster.labels["flannel_network_cidr"], "")
}

output "service_network_cidr" {
  description = "The service network CIDR"
  value       = try(openstack_containerinfra_cluster_v1.cluster.labels["service_cluster_ip_range"], "")
}

# Stack Information
output "stack_id" {
  description = "The Heat stack ID"
  value       = openstack_containerinfra_cluster_v1.cluster.stack_id
}

# Discovery URL
output "discovery_url" {
  description = "The discovery URL for the cluster"
  value       = openstack_containerinfra_cluster_v1.cluster.discovery_url
  sensitive   = true
}

# Kubernetes Version
output "kubernetes_version" {
  description = "The Kubernetes version of the cluster"
  value       = try(openstack_containerinfra_cluster_v1.cluster.labels["kube_tag"], var.kubernetes_version)
}

# Connection Commands
output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "export KUBECONFIG=${local_file.kubeconfig.filename}"
}

output "cluster_info_command" {
  description = "Command to get cluster info"
  value       = "KUBECONFIG=${local_file.kubeconfig.filename} kubectl cluster-info"
}

output "get_nodes_command" {
  description = "Command to get cluster nodes"
  value       = "KUBECONFIG=${local_file.kubeconfig.filename} kubectl get nodes"
}

# Monitoring URLs (if monitoring is installed)
output "grafana_url" {
  description = "Grafana dashboard URL (if monitoring is installed)"
  value       = var.install_monitoring ? "http://${try(openstack_containerinfra_cluster_v1.cluster.api_address, "localhost")}:30000" : ""
}

output "prometheus_url" {
  description = "Prometheus URL (if monitoring is installed)"
  value       = var.install_monitoring ? "http://${try(openstack_containerinfra_cluster_v1.cluster.api_address, "localhost")}:30001" : ""
}

# Cluster Labels
output "cluster_labels" {
  description = "All cluster labels"
  value       = openstack_containerinfra_cluster_v1.cluster.labels
  sensitive   = true
}

# Auto-scaling Information
output "auto_scaling_enabled" {
  description = "Whether auto-scaling is enabled"
  value       = try(openstack_containerinfra_cluster_v1.cluster.labels["auto_scaling_enabled"] == "true", false)
}

output "min_node_count" {
  description = "Minimum node count for auto-scaling"
  value       = try(tonumber(openstack_containerinfra_cluster_v1.cluster.labels["min_node_count"]), 0)
}

output "max_node_count" {
  description = "Maximum node count for auto-scaling"
  value       = try(tonumber(openstack_containerinfra_cluster_v1.cluster.labels["max_node_count"]), 0)
}

# Environment Information
output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "tags" {
  description = "Resource tags"
  value       = var.tags
}

