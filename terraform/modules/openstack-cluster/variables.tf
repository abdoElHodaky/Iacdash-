# Cluster Configuration
variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
  default     = "gateway-mesh-openstack"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.cluster_name))
    error_message = "Cluster name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "cluster_template_name" {
  description = "Name of the Magnum cluster template to use"
  type        = string
  default     = "kubernetes-1.28"
}

variable "kubernetes_version" {
  description = "Kubernetes version tag"
  type        = string
  default     = "v1.28.0"
}

# Node Configuration
variable "master_count" {
  description = "Number of master nodes"
  type        = number
  default     = 3
  
  validation {
    condition     = var.master_count >= 1 && var.master_count <= 5
    error_message = "Master count must be between 1 and 5."
  }
}

variable "node_count" {
  description = "Initial number of worker nodes"
  type        = number
  default     = 3
  
  validation {
    condition     = var.node_count >= 1 && var.node_count <= 100
    error_message = "Node count must be between 1 and 100."
  }
}

# Auto-scaling Configuration
variable "auto_scaling_enabled" {
  description = "Enable auto-scaling for worker nodes"
  type        = bool
  default     = true
}

variable "min_node_count" {
  description = "Minimum number of worker nodes for auto-scaling"
  type        = number
  default     = 3
}

variable "max_node_count" {
  description = "Maximum number of worker nodes for auto-scaling"
  type        = number
  default     = 10
  
  validation {
    condition     = var.max_node_count >= var.min_node_count
    error_message = "Maximum node count must be greater than or equal to minimum node count."
  }
}

# SSH Access
variable "keypair_name" {
  description = "Name of the OpenStack keypair for SSH access to nodes"
  type        = string
}

# Network Configuration
variable "flannel_network_cidr" {
  description = "CIDR for the Flannel network"
  type        = string
  default     = "10.100.0.0/16"
}

variable "flannel_network_subnets" {
  description = "Subnets for the Flannel network"
  type        = string
  default     = "10.100.0.0/24"
}

variable "flannel_backend" {
  description = "Flannel backend type"
  type        = string
  default     = "vxlan"
  
  validation {
    condition     = contains(["vxlan", "host-gw", "udp"], var.flannel_backend)
    error_message = "Flannel backend must be one of: vxlan, host-gw, udp."
  }
}

# Docker Configuration
variable "docker_storage_driver" {
  description = "Docker storage driver"
  type        = string
  default     = "overlay2"
}

variable "docker_volume_size" {
  description = "Size of Docker volume in GB"
  type        = number
  default     = 20
  
  validation {
    condition     = var.docker_volume_size >= 10 && var.docker_volume_size <= 1000
    error_message = "Docker volume size must be between 10 and 1000 GB."
  }
}

# Heat Configuration
variable "heat_container_agent_tag" {
  description = "Heat container agent tag"
  type        = string
  default     = "train-stable-1"
}

# Features Configuration
variable "monitoring_enabled" {
  description = "Enable cluster monitoring"
  type        = bool
  default     = true
}

variable "logging_enabled" {
  description = "Enable cluster logging"
  type        = bool
  default     = true
}

variable "dashboard_enabled" {
  description = "Enable Kubernetes dashboard"
  type        = bool
  default     = false
}

variable "ingress_controller" {
  description = "Ingress controller to install"
  type        = string
  default     = "istio"
  
  validation {
    condition     = contains(["istio", "nginx", "traefik", "none"], var.ingress_controller)
    error_message = "Ingress controller must be one of: istio, nginx, traefik, none."
  }
}

# Timeouts
variable "create_timeout" {
  description = "Timeout for cluster creation"
  type        = string
  default     = "60m"
}

variable "update_timeout" {
  description = "Timeout for cluster updates"
  type        = string
  default     = "60m"
}

variable "delete_timeout" {
  description = "Timeout for cluster deletion"
  type        = string
  default     = "30m"
}

variable "cluster_ready_wait_time" {
  description = "Time to wait for cluster to be ready (seconds)"
  type        = number
  default     = 120
}

# Kubeconfig
variable "kubeconfig_path" {
  description = "Path to save kubeconfig file"
  type        = string
  default     = "."
}

# Optional Features
variable "create_admin_service_account" {
  description = "Create cluster admin service account"
  type        = bool
  default     = true
}

variable "install_monitoring" {
  description = "Install Prometheus monitoring stack"
  type        = bool
  default     = false
}

variable "grafana_admin_password" {
  description = "Grafana admin password (only used if install_monitoring is true)"
  type        = string
  default     = "admin123"
  sensitive   = true
}

# Labels and Tags
variable "additional_labels" {
  description = "Additional labels to apply to the cluster"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags to apply to cluster resources"
  type        = list(string)
  default     = ["kubernetes", "gateway-api", "service-mesh"]
}

# Environment
variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
  default     = "development"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

