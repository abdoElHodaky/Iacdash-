# Environment Configuration
variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

# OpenStack Configuration
variable "openstack_auth_url" {
  description = "OpenStack authentication URL"
  type        = string
}

variable "openstack_region" {
  description = "OpenStack region"
  type        = string
  default     = "RegionOne"
}

variable "openstack_project_id" {
  description = "OpenStack project ID"
  type        = string
}

variable "openstack_domain_id" {
  description = "OpenStack domain ID"
  type        = string
  default     = "default"
}

variable "openstack_username" {
  description = "OpenStack username"
  type        = string
  sensitive   = true
}

variable "openstack_password" {
  description = "OpenStack password"
  type        = string
  sensitive   = true
}

# Volume Types
variable "volume_types" {
  description = "List of available volume types in OpenStack"
  type        = list(string)
  default     = ["__DEFAULT__", "ssd", "hdd", "nvme"]
}

# Storage Classes Configuration
variable "storage_classes" {
  description = "Storage classes to create"
  type = map(object({
    volume_type            = string
    performance_tier       = string
    is_default            = bool
    reclaim_policy        = string
    volume_binding_mode   = string
    allow_volume_expansion = bool
    availability_zone     = optional(string)
    fstype               = optional(string)
    additional_parameters = optional(map(string), {})
  }))
  
  default = {
    "cinder-ssd" = {
      volume_type            = "ssd"
      performance_tier       = "high"
      is_default            = true
      reclaim_policy        = "Delete"
      volume_binding_mode   = "WaitForFirstConsumer"
      allow_volume_expansion = true
      fstype               = "ext4"
      additional_parameters = {}
    }
    
    "cinder-hdd" = {
      volume_type            = "hdd"
      performance_tier       = "standard"
      is_default            = false
      reclaim_policy        = "Delete"
      volume_binding_mode   = "WaitForFirstConsumer"
      allow_volume_expansion = true
      fstype               = "ext4"
      additional_parameters = {}
    }
    
    "cinder-nvme" = {
      volume_type            = "nvme"
      performance_tier       = "premium"
      is_default            = false
      reclaim_policy        = "Delete"
      volume_binding_mode   = "WaitForFirstConsumer"
      allow_volume_expansion = true
      fstype               = "ext4"
      additional_parameters = {}
    }
    
    "cinder-retain" = {
      volume_type            = "ssd"
      performance_tier       = "high"
      is_default            = false
      reclaim_policy        = "Retain"
      volume_binding_mode   = "WaitForFirstConsumer"
      allow_volume_expansion = true
      fstype               = "ext4"
      additional_parameters = {}
    }
  }
}

# Persistent Volumes Configuration
variable "persistent_volumes" {
  description = "Pre-provisioned persistent volumes"
  type = map(object({
    name                 = string
    description          = string
    size                 = number
    volume_type          = string
    availability_zone    = string
    enable_online_resize = bool
    purpose              = string
    access_modes         = list(string)
    reclaim_policy       = string
    storage_class        = string
    fstype              = string
    metadata            = optional(map(string), {})
    scheduler_hints     = optional(object({
      local_to_instance = optional(string)
      different_host    = optional(list(string))
      same_host         = optional(list(string))
    }))
  }))
  
  default = {}
}

# Volume Snapshots Configuration
variable "volume_snapshots" {
  description = "Volume snapshots to create"
  type = map(object({
    name             = string
    description      = string
    source_volume_id = string
    size            = number
    backup_type     = string
  }))
  
  default = {}
}

# Volume Snapshot Classes
variable "volume_snapshot_classes" {
  description = "Volume snapshot classes configuration"
  type = map(object({
    deletion_policy = string
    parameters     = optional(map(string), {})
  }))
  
  default = {
    "cinder-snapshots" = {
      deletion_policy = "Delete"
      parameters = {}
    }
    
    "cinder-snapshots-retain" = {
      deletion_policy = "Retain"
      parameters = {}
    }
  }
}

# CSI Driver Configuration
variable "install_csi_driver" {
  description = "Install OpenStack Cinder CSI driver"
  type        = bool
  default     = true
}

variable "csi_driver_version" {
  description = "Version of the Cinder CSI driver Helm chart"
  type        = string
  default     = "2.28.0"
}

variable "csi_driver_image_tag" {
  description = "Image tag for the Cinder CSI driver"
  type        = string
  default     = "v1.28.0"
}

variable "csi_driver_namespace" {
  description = "Namespace for CSI driver installation"
  type        = string
  default     = "kube-system"
}

variable "csi_driver_node_selector" {
  description = "Node selector for CSI driver pods"
  type        = map(string)
  default     = {}
}

variable "csi_driver_tolerations" {
  description = "Tolerations for CSI driver pods"
  type = list(object({
    key      = optional(string)
    operator = optional(string)
    value    = optional(string)
    effect   = optional(string)
  }))
  default = []
}

# Backup Configuration
variable "backup_policies" {
  description = "Backup policies for volumes"
  type = map(object({
    schedule       = string
    timezone       = string
    volume_ids     = list(string)
    retention_days = number
    backup_prefix  = string
  }))
  
  default = {}
}

variable "backup_namespace" {
  description = "Namespace for backup jobs"
  type        = string
  default     = "backup-system"
}

# Performance Optimization
variable "performance_optimization" {
  description = "Performance optimization settings"
  type = object({
    enable_multipath     = optional(bool, false)
    io_timeout          = optional(number, 30)
    volume_attach_limit = optional(number, 256)
    enable_topology     = optional(bool, true)
  })
  default = {}
}

# Cost Optimization
variable "cost_optimization" {
  description = "Cost optimization settings"
  type = object({
    enable_volume_encryption = optional(bool, false)
    default_volume_size     = optional(number, 20)
    enable_compression      = optional(bool, false)
    lifecycle_policies      = optional(map(object({
      transition_days = number
      storage_class   = string
    })), {})
  })
  default = {}
}

# Monitoring Configuration
variable "monitoring_enabled" {
  description = "Enable storage monitoring"
  type        = bool
  default     = true
}

variable "monitoring_namespace" {
  description = "Namespace for monitoring resources"
  type        = string
  default     = "monitoring"
}

# Security Configuration
variable "security_settings" {
  description = "Security settings for storage"
  type = object({
    enable_encryption_at_rest = optional(bool, true)
    encryption_key_id        = optional(string)
    enable_access_logging    = optional(bool, true)
    allowed_availability_zones = optional(list(string), [])
  })
  default = {}
}

# Disaster Recovery
variable "disaster_recovery" {
  description = "Disaster recovery configuration"
  type = object({
    enable_cross_region_backup = optional(bool, false)
    backup_region             = optional(string)
    replication_schedule      = optional(string, "0 2 * * *")
    retention_policy          = optional(object({
      daily_backups   = optional(number, 7)
      weekly_backups  = optional(number, 4)
      monthly_backups = optional(number, 12)
    }), {})
  })
  default = {}
}

# Resource Tagging
variable "tags" {
  description = "Tags to apply to all storage resources"
  type        = map(string)
  default = {
    "managed-by" = "terraform"
    "component"  = "storage"
  }
}

variable "additional_labels" {
  description = "Additional labels for Kubernetes resources"
  type        = map(string)
  default     = {}
}

