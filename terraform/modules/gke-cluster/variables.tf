variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "location" {
  description = "GKE cluster location (region or zone)"
  type        = string
  default     = "us-central1"
}

variable "network" {
  description = "VPC network name"
  type        = string
  default     = "default"
}

variable "subnetwork" {
  description = "VPC subnetwork name"
  type        = string
  default     = "default"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the cluster"
  type        = string
  default     = "1.28"
}

variable "cluster_secondary_range_name" {
  description = "Secondary range name for cluster pods"
  type        = string
  default     = "gke-pods"
}

variable "services_secondary_range_name" {
  description = "Secondary range name for services"
  type        = string
  default     = "gke-services"
}

variable "master_authorized_networks" {
  description = "Master authorized networks configuration"
  type = object({
    gcp_public_cidrs_access_enabled = optional(bool, false)
    cidr_blocks = list(object({
      cidr_block   = string
      display_name = string
    }))
  })
  default = null
}

variable "private_cluster" {
  description = "Enable private cluster"
  type        = bool
  default     = false
}

variable "private_endpoint" {
  description = "Enable private endpoint"
  type        = bool
  default     = false
}

variable "master_ipv4_cidr_block" {
  description = "Master IPv4 CIDR block"
  type        = string
  default     = "172.16.0.0/28"
}

variable "maintenance_start_time" {
  description = "Maintenance window start time"
  type        = string
  default     = "03:00"
}

variable "enable_managed_prometheus" {
  description = "Enable GKE managed Prometheus"
  type        = bool
  default     = false
}

variable "use_gke_gateway_addon" {
  description = "Use GKE Gateway API addon instead of manual CRDs"
  type        = bool
  default     = true
}

variable "node_pools" {
  description = "Node pool configurations"
  type = map(object({
    node_count    = number
    machine_type  = string
    disk_size_gb  = number
    disk_type     = string
    preemptible   = bool
    labels        = map(string)
    tags          = list(string)
    max_surge     = number
    max_unavailable = number
    autoscaling = optional(object({
      min_node_count = number
      max_node_count = number
    }))
  }))
  default = {
    primary = {
      node_count      = 3
      machine_type    = "e2-standard-4"
      disk_size_gb    = 100
      disk_type       = "pd-standard"
      preemptible     = false
      labels          = {}
      tags            = ["gke-node"]
      max_surge       = 1
      max_unavailable = 0
      autoscaling = {
        min_node_count = 1
        max_node_count = 5
      }
    }
  }
}

variable "install_istio" {
  description = "Whether to install Istio service mesh"
  type        = bool
  default     = true
}

variable "istio_version" {
  description = "Version of Istio to install"
  type        = string
  default     = "1.20.1"
}

variable "install_monitoring" {
  description = "Whether to install monitoring stack (ignored if managed Prometheus is enabled)"
  type        = bool
  default     = true
}

variable "prometheus_stack_version" {
  description = "Version of Prometheus stack to install"
  type        = string
  default     = "55.5.0"
}

variable "prometheus_retention" {
  description = "Prometheus data retention period"
  type        = string
  default     = "30d"
}

variable "prometheus_storage_size" {
  description = "Prometheus storage size"
  type        = string
  default     = "50Gi"
}

variable "grafana_admin_password" {
  description = "Admin password for Grafana"
  type        = string
  sensitive   = true
}

variable "grafana_storage_size" {
  description = "Grafana storage size"
  type        = string
  default     = "10Gi"
}

