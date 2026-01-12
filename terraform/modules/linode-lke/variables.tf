variable "cluster_name" {
  description = "Name of the LKE cluster"
  type        = string
}

variable "region" {
  description = "Linode region for the cluster"
  type        = string
  default     = "us-east"
  
  validation {
    condition = contains([
      "us-east", "us-west", "us-central", "us-southeast",
      "eu-west", "eu-central", "ap-south", "ap-northeast",
      "ap-southeast", "ca-central"
    ], var.region)
    error_message = "Region must be a valid Linode region."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version for the cluster"
  type        = string
  default     = "1.28"
}

variable "node_pools" {
  description = "Node pool configurations"
  type = list(object({
    type  = string
    count = number
    autoscaler = optional(object({
      min = number
      max = number
    }))
  }))
  default = [
    {
      type  = "g6-standard-2"
      count = 3
      autoscaler = {
        min = 1
        max = 5
      }
    }
  ]
}

variable "control_plane_acl" {
  description = "Control plane access control configuration"
  type = object({
    high_availability = optional(bool, false)
    acl = optional(object({
      enabled = bool
      addresses = optional(list(object({
        ipv4 = optional(list(string))
        ipv6 = optional(list(string))
      })))
    }))
  })
  default = null
}

variable "tags" {
  description = "Tags to apply to the cluster"
  type        = list(string)
  default     = ["gateway-api", "istio", "terraform"]
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

