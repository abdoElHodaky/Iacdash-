# Cluster Information
output "cluster_name" {
  description = "Name of the GKE cluster"
  value       = module.gke_cluster.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for the GKE cluster"
  value       = module.gke_cluster.cluster_endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "CA certificate for the GKE cluster"
  value       = module.gke_cluster.cluster_ca_certificate
  sensitive   = true
}

output "cluster_location" {
  description = "Location of the GKE cluster"
  value       = module.gke_cluster.cluster_location
}

output "cluster_status" {
  description = "Current status of the cluster"
  value       = module.gke_cluster.cluster_status
}

# Network Information
output "vpc_network_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.vpc.name
}

output "subnet_name" {
  description = "Name of the subnet"
  value       = google_compute_subnetwork.subnet.name
}

output "subnet_cidr" {
  description = "CIDR block of the subnet"
  value       = google_compute_subnetwork.subnet.ip_cidr_range
}

# Kubeconfig
output "kubeconfig_raw" {
  description = "Raw kubeconfig for accessing the cluster"
  value       = module.gke_cluster.kubeconfig_raw
  sensitive   = true
}

output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = module.gke_cluster.kubectl_config_command
}

# Service Mesh Information
output "istio_installed" {
  description = "Whether Istio is installed"
  value       = module.gke_cluster.istio_installed
}

# Monitoring Information
output "monitoring_installed" {
  description = "Whether monitoring stack is installed"
  value       = module.gke_cluster.monitoring_installed
}

output "managed_prometheus_enabled" {
  description = "Whether GKE managed Prometheus is enabled"
  value       = module.gke_cluster.managed_prometheus_enabled
}

output "prometheus_access" {
  description = "Prometheus access information"
  value       = module.gke_cluster.prometheus_access
  sensitive   = true
}

output "grafana_access" {
  description = "Grafana access information"
  value       = module.gke_cluster.grafana_access
  sensitive   = true
}

# Gateway API Information
output "gateway_api_addon_enabled" {
  description = "Whether Gateway API addon is enabled"
  value       = module.gke_cluster.gateway_api_addon_enabled
}

# Node Pools Information
output "node_pools" {
  description = "Node pool information"
  value       = module.gke_cluster.node_pools
}

# Service Account
output "service_account_email" {
  description = "Email of the GKE node service account"
  value       = module.gke_cluster.service_account_email
}
