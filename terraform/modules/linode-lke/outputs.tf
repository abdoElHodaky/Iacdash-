output "cluster_id" {
  description = "LKE cluster ID"
  value       = linode_lke_cluster.gateway_cluster.id
}

output "cluster_name" {
  description = "Name of the created LKE cluster"
  value       = linode_lke_cluster.gateway_cluster.label
}

output "kubeconfig" {
  description = "Kubeconfig for cluster access"
  value       = base64decode(linode_lke_cluster.gateway_cluster.kubeconfig)
  sensitive   = true
}

output "api_endpoints" {
  description = "Kubernetes API endpoints"
  value       = linode_lke_cluster.gateway_cluster.api_endpoints
}

output "status" {
  description = "Cluster status"
  value       = linode_lke_cluster.gateway_cluster.status
}

output "dashboard_url" {
  description = "Kubernetes dashboard URL"
  value       = linode_lke_cluster.gateway_cluster.dashboard_url
}

output "node_pools" {
  description = "Node pool information"
  value = {
    for pool in linode_lke_cluster.gateway_cluster.pool :
    pool.type => {
      count = pool.count
      nodes = pool.nodes
    }
  }
}

output "istio_installed" {
  description = "Whether Istio was installed"
  value       = var.install_istio
}

output "monitoring_installed" {
  description = "Whether monitoring stack was installed"
  value       = var.install_monitoring
}

output "istio_gateway_ip" {
  description = "Istio ingress gateway external IP"
  value       = var.install_istio ? "Check: kubectl get svc -n istio-ingress istio-ingressgateway" : "Not installed"
}

output "grafana_access" {
  description = "Grafana access information"
  value = var.install_monitoring ? {
    url      = "Check LoadBalancer IP: kubectl get svc -n monitoring prometheus-grafana"
    username = "admin"
    password = "[REDACTED]"
  } : {
    url      = "Not installed"
    username = null
    password = null
  }
}

output "prometheus_access" {
  description = "Prometheus access information"
  value = var.install_monitoring ? {
    url = "Port-forward: kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
  } : {
    url = "Not installed"
  }
}
