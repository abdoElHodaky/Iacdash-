# OpenStack Storage Example
# Demonstrates comprehensive storage configuration for production workloads

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.53"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

# Configure providers
provider "openstack" {
  # Credentials from environment variables or openrc.sh
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

# Production storage configuration
module "openstack_storage" {
  source = "../../modules/openstack-storage"
  
  environment = "production"
  
  # OpenStack configuration
  openstack_auth_url   = var.openstack_auth_url
  openstack_region     = var.openstack_region
  openstack_project_id = var.openstack_project_id
  openstack_domain_id  = var.openstack_domain_id
  openstack_username   = var.openstack_username
  openstack_password   = var.openstack_password
  
  # Storage classes for different performance tiers
  storage_classes = {
    "cinder-ssd-production" = {
      volume_type            = "ssd"
      performance_tier       = "high"
      is_default            = true
      reclaim_policy        = "Delete"
      volume_binding_mode   = "WaitForFirstConsumer"
      allow_volume_expansion = true
      fstype               = "ext4"
      additional_parameters = {
        "cinder.csi.openstack.org/fstype" = "ext4"
      }
    }
    
    "cinder-hdd-backup" = {
      volume_type            = "hdd"
      performance_tier       = "standard"
      is_default            = false
      reclaim_policy        = "Retain"
      volume_binding_mode   = "WaitForFirstConsumer"
      allow_volume_expansion = true
      fstype               = "ext4"
      additional_parameters = {}
    }
    
    "cinder-nvme-database" = {
      volume_type            = "nvme"
      performance_tier       = "premium"
      is_default            = false
      reclaim_policy        = "Delete"
      volume_binding_mode   = "WaitForFirstConsumer"
      allow_volume_expansion = true
      fstype               = "ext4"
      additional_parameters = {
        "cinder.csi.openstack.org/fstype" = "ext4"
      }
    }
  }
  
  # Pre-provisioned volumes for critical applications
  persistent_volumes = {
    "database-primary" = {
      name                 = "postgres-primary-volume"
      description          = "Primary PostgreSQL database volume"
      size                 = 100
      volume_type          = "nvme"
      availability_zone    = "nova"
      enable_online_resize = true
      purpose              = "database"
      access_modes         = ["ReadWriteOnce"]
      reclaim_policy       = "Retain"
      storage_class        = "cinder-nvme-database"
      fstype              = "ext4"
      metadata = {
        application = "postgresql"
        tier        = "database"
        backup      = "enabled"
      }
    }
    
    "redis-cache" = {
      name                 = "redis-cache-volume"
      description          = "Redis cache storage volume"
      size                 = 50
      volume_type          = "ssd"
      availability_zone    = "nova"
      enable_online_resize = true
      purpose              = "cache"
      access_modes         = ["ReadWriteOnce"]
      reclaim_policy       = "Delete"
      storage_class        = "cinder-ssd-production"
      fstype              = "ext4"
      metadata = {
        application = "redis"
        tier        = "cache"
      }
    }
    
    "backup-storage" = {
      name                 = "backup-storage-volume"
      description          = "Backup storage for applications"
      size                 = 500
      volume_type          = "hdd"
      availability_zone    = "nova"
      enable_online_resize = true
      purpose              = "backup"
      access_modes         = ["ReadWriteOnce"]
      reclaim_policy       = "Retain"
      storage_class        = "cinder-hdd-backup"
      fstype              = "ext4"
      metadata = {
        application = "backup"
        tier        = "storage"
        retention   = "long-term"
      }
    }
  }
  
  # Volume snapshot classes
  volume_snapshot_classes = {
    "cinder-snapshots-production" = {
      deletion_policy = "Delete"
      parameters = {
        "cinder.csi.openstack.org/snapshot-type" = "standard"
      }
    }
    
    "cinder-snapshots-backup" = {
      deletion_policy = "Retain"
      parameters = {
        "cinder.csi.openstack.org/snapshot-type" = "backup"
      }
    }
  }
  
  # Backup policies
  backup_policies = {
    "database-backup" = {
      schedule       = "0 2 * * *"  # Daily at 2 AM
      timezone       = "UTC"
      volume_ids     = ["postgres-primary-volume"]
      retention_days = 30
      backup_prefix  = "db-backup"
    }
    
    "weekly-backup" = {
      schedule       = "0 3 * * 0"  # Weekly on Sunday at 3 AM
      timezone       = "UTC"
      volume_ids     = ["postgres-primary-volume", "backup-storage-volume"]
      retention_days = 90
      backup_prefix  = "weekly-backup"
    }
  }
  
  # CSI Driver configuration
  install_csi_driver     = true
  csi_driver_version     = "2.28.0"
  csi_driver_namespace   = "kube-system"
  
  # Monitoring
  monitoring_enabled    = true
  monitoring_namespace  = "monitoring"
  
  # Security settings
  security_settings = {
    enable_encryption_at_rest = true
    enable_access_logging    = true
    allowed_availability_zones = ["nova"]
  }
  
  # Cost optimization
  cost_optimization = {
    enable_volume_encryption = true
    default_volume_size     = 20
    enable_compression      = false
  }
  
  # Disaster recovery
  disaster_recovery = {
    enable_cross_region_backup = false
    replication_schedule      = "0 4 * * *"
    retention_policy = {
      daily_backups   = 7
      weekly_backups  = 4
      monthly_backups = 12
    }
  }
  
  # Resource tags
  tags = {
    "environment"   = "production"
    "project"       = var.project_name
    "managed-by"    = "terraform"
    "component"     = "storage"
    "cost-center"   = "infrastructure"
  }
}

# Example PVC for applications
resource "kubernetes_persistent_volume_claim_v1" "example_app_storage" {
  metadata {
    name      = "example-app-storage"
    namespace = "default"
    labels = {
      "app.kubernetes.io/name" = "example-app"
      "environment"            = "production"
    }
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "cinder-ssd-production"
    
    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }

  depends_on = [module.openstack_storage]
}

# Example StatefulSet using the storage
resource "kubernetes_stateful_set_v1" "example_database" {
  metadata {
    name      = "example-database"
    namespace = "default"
    labels = {
      "app.kubernetes.io/name" = "example-database"
      "environment"            = "production"
    }
  }

  spec {
    service_name = "example-database"
    replicas     = 1

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "example-database"
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "example-database"
          "environment"            = "production"
        }
      }

      spec {
        container {
          name  = "postgres"
          image = "postgres:15-alpine"

          env {
            name  = "POSTGRES_DB"
            value = "exampledb"
          }

          env {
            name  = "POSTGRES_USER"
            value = "postgres"
          }

          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = "postgres-secret"
                key  = "password"
              }
            }
          }

          port {
            container_port = 5432
            name          = "postgres"
          }

          volume_mount {
            name       = "postgres-storage"
            mount_path = "/var/lib/postgresql/data"
          }

          resources {
            requests = {
              cpu    = "500m"
              memory = "1Gi"
            }
            limits = {
              cpu    = "2000m"
              memory = "4Gi"
            }
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "postgres-storage"
        labels = {
          "app.kubernetes.io/name" = "example-database"
          "environment"            = "production"
        }
      }

      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = "cinder-nvme-database"
        
        resources {
          requests = {
            storage = "50Gi"
          }
        }
      }
    }
  }

  depends_on = [module.openstack_storage]
}

# Output important information
output "storage_classes" {
  description = "Created storage classes"
  value       = keys(module.openstack_storage.storage_classes)
}

output "persistent_volumes" {
  description = "Created persistent volumes"
  value       = keys(module.openstack_storage.persistent_volumes)
}

output "backup_policies" {
  description = "Configured backup policies"
  value       = keys(module.openstack_storage.backup_policies)
}

