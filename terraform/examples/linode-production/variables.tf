variable "linode_token" {
  description = "Linode API token"
  type        = string
  sensitive   = true
}

variable "cluster_name" {
  description = "Name of the LKE cluster"
  type        = string
  default     = "gateway-production"
}

variable "region" {
  description = "Linode region for the cluster"
  type        = string
  default     = "us-east"
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
      type  = "g6-standard-4"
      count = 3
      autoscaler = {
        min = 2
        max = 10
      }
    }
  ]
}

variable "control_plane_acl" {
  description = "Control plane access control configuration"
  type = object({
    high_availability = optional(bool, true)
    acl = optional(object({
      enabled = bool
      addresses = optional(list(object({
        ipv4 = optional(list(string))
        ipv6 = optional(list(string))
      })))
    }))
  })
  default = {
    high_availability = true
    acl = {
      enabled = true
      addresses = [
        {
          ipv4 = ["0.0.0.0/0"] # Replace with your office/VPN IPs
        }
      ]
    }
  }
}

variable "tags" {
  description = "Tags to apply to the cluster"
  type        = list(string)
  default     = ["gateway-api", "istio", "production", "terraform"]
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
  default     = "90d"
}

variable "prometheus_storage_size" {
  description = "Prometheus storage size"
  type        = string
  default     = "100Gi"
}

variable "grafana_admin_password" {
  description = "Admin password for Grafana"
  type        = string
  sensitive   = true
}

variable "grafana_storage_size" {
  description = "Grafana storage size"
  type        = string
  default     = "20Gi"
}

