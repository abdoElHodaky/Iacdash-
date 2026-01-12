output "cluster_name" {
  description = "Name of the created KinD cluster"
  value       = kind_cluster.default.name
}

output "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  value       = kind_cluster.default.kubeconfig_path
}

output "cluster_endpoint" {
  description = "Kubernetes cluster endpoint"
  value       = kind_cluster.default.endpoint
}

output "client_certificate" {
  description = "Client certificate for cluster access"
  value       = kind_cluster.default.client_certificate
  sensitive   = true
}

output "client_key" {
  description = "Client key for cluster access"
  value       = kind_cluster.default.client_key
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Cluster CA certificate"
  value       = kind_cluster.default.cluster_ca_certificate
  sensitive   = true
}

output "istio_installed" {
  description = "Whether Istio was installed"
  value       = var.install_istio
}

output "monitoring_installed" {
  description = "Whether monitoring stack was installed"
  value       = var.install_monitoring
}

output "grafana_url" {
  description = "Grafana access URL (requires port-forward)"
  value       = var.install_monitoring ? "kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80" : "Not installed"
}

output "prometheus_url" {
  description = "Prometheus access URL (requires port-forward)"
  value       = var.install_monitoring ? "kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090" : "Not installed"
}

