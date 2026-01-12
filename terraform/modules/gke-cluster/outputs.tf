output "cluster_id" {
  description = "GKE cluster ID"
  value       = google_container_cluster.gateway_cluster.id
}

output "cluster_name" {
  description = "Name of the created GKE cluster"
  value       = google_container_cluster.gateway_cluster.name
}

output "cluster_location" {
  description = "Location of the GKE cluster"
  value       = google_container_cluster.gateway_cluster.location
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = google_container_cluster.gateway_cluster.endpoint
}

output "cluster_ca_certificate" {
  description = "Cluster CA certificate"
  value       = base64decode(google_container_cluster.gateway_cluster.master_auth.0.cluster_ca_certificate)
  sensitive   = true
}

output "client_certificate" {
  description = "Client certificate for cluster access"
  value       = google_container_cluster.gateway_cluster.master_auth.0.client_certificate
  sensitive   = true
}

output "client_key" {
  description = "Client key for cluster access"
  value       = google_container_cluster.gateway_cluster.master_auth.0.client_key
  sensitive   = true
}

output "kubeconfig_raw" {
  description = "Raw kubeconfig for cluster access"
  value = templatefile("${path.module}/kubeconfig.tpl", {
    cluster_name           = google_container_cluster.gateway_cluster.name
    cluster_endpoint       = google_container_cluster.gateway_cluster.endpoint
    cluster_ca_certificate = google_container_cluster.gateway_cluster.master_auth.0.cluster_ca_certificate
    project_id             = var.project_id
    location               = google_container_cluster.gateway_cluster.location
  })
  sensitive = true
}

output "node_pools" {
  description = "Node pool information"
  value = {
    for pool_name, pool in google_container_node_pool.primary_nodes :
    pool_name => {
      name         = pool.name
      location     = pool.location
      node_count   = pool.node_count
      machine_type = pool.node_config[0].machine_type
      disk_size_gb = pool.node_config[0].disk_size_gb
      disk_type    = pool.node_config[0].disk_type
      preemptible  = pool.node_config[0].preemptible
      version      = pool.version
    }
  }
}

output "service_account_email" {
  description = "Email of the GKE node service account"
  value       = google_service_account.gke_node_sa.email
}

output "network" {
  description = "Network used by the cluster"
  value       = var.network
}

output "subnetwork" {
  description = "Subnetwork used by the cluster"
  value       = var.subnetwork
}

output "istio_installed" {
  description = "Whether Istio was installed"
  value       = var.install_istio
}

output "monitoring_installed" {
  description = "Whether monitoring stack was installed"
  value       = var.install_monitoring && !var.enable_managed_prometheus
}

output "managed_prometheus_enabled" {
  description = "Whether GKE managed Prometheus is enabled"
  value       = var.enable_managed_prometheus
}

output "gateway_api_addon_enabled" {
  description = "Whether GKE Gateway API addon is enabled"
  value       = var.use_gke_gateway_addon
}

output "cluster_status" {
  description = "Current status of the cluster"
  value       = google_container_cluster.gateway_cluster.endpoint != null ? "RUNNING" : "PROVISIONING"
}

output "grafana_access" {
  description = "Grafana access information"
  value = var.install_monitoring && !var.enable_managed_prometheus ? {
    url      = "Port-forward: kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
    username = "admin"
    password = "[REDACTED]"
    } : var.enable_managed_prometheus ? {
    url      = "Use GCP Console: Monitoring > Dashboards"
    username = "GCP IAM"
    password = "GCP IAM"
  } : "Not installed"
}

output "prometheus_access" {
  description = "Prometheus access information"
  value = var.install_monitoring && !var.enable_managed_prometheus ? {
    url = "Port-forward: kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
    } : var.enable_managed_prometheus ? {
    url = "Use GCP Console: Monitoring > Metrics Explorer"
  } : "Not installed"
}

output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.gateway_cluster.name} --location ${google_container_cluster.gateway_cluster.location} --project ${var.project_id}"
}
