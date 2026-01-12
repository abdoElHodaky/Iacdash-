variable "cluster_name" {
  description = "Name of the KinD cluster"
  type        = string
  default     = "gateway-dev"
}

variable "worker_nodes" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
  
  validation {
    condition     = var.worker_nodes >= 1 && var.worker_nodes <= 10
    error_message = "Worker nodes must be between 1 and 10."
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
  description = "Whether to install monitoring stack"
  type        = bool
  default     = true
}

variable "prometheus_stack_version" {
  description = "Version of Prometheus stack to install"
  type        = string
  default     = "55.5.0"
}

variable "grafana_admin_password" {
  description = "Admin password for Grafana"
  type        = string
  default     = "admin"
  sensitive   = true
}

