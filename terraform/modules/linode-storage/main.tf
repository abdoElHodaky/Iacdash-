terraform {
  required_version = ">= 1.6.0"
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 2.9"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }
}

# Linode Block Storage Volumes
resource "linode_volume" "block_storage_volumes" {
  for_each = var.block_storage_volumes

  label  = each.value.label
  size   = each.value.size
  region = each.value.region
  
  # Linode instance attachment (optional)
  linode_id = each.value.linode_id

  tags = concat(
    [
      "environment:${var.environment}",
      "managed-by:terraform",
      "purpose:${each.value.purpose}",
      "storage-tier:${each.value.storage_tier}"
    ],
    each.value.additional_tags
  )
}

# Storage Classes for Linode Block Storage
resource "kubernetes_storage_class_v1" "linode_storage_classes" {
  for_each = var.storage_classes

  metadata {
    name = each.key
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = each.value.is_default ? "true" : "false"
    }
    labels = {
      "storage.linode.io/type"        = each.value.storage_type
      "storage.linode.io/performance" = each.value.performance_tier
      "environment"                   = var.environment
    }
  }

  storage_provisioner    = "linodebs.csi.linode.com"
  reclaim_policy        = each.value.reclaim_policy
  volume_binding_mode   = each.value.volume_binding_mode
  allow_volume_expansion = each.value.allow_volume_expansion

  parameters = merge(
    {
      "linodebs.csi.linode.com/filesystem" = each.value.filesystem
      "linodebs.csi.linode.com/region"     = each.value.region
    },
    each.value.enable_encryption ? {
      "linodebs.csi.linode.com/luks-encrypted" = "true"
    } : {},
    each.value.additional_parameters
  )
}

# Kubernetes Persistent Volumes for pre-provisioned Linode volumes
resource "kubernetes_persistent_volume_v1" "linode_pvs" {
  for_each = var.block_storage_volumes

  metadata {
    name = each.value.label
    labels = {
      "storage.linode.io/volume-id"   = linode_volume.block_storage_volumes[each.key].id
      "storage.linode.io/region"      = each.value.region
      "environment"                   = var.environment
      "purpose"                       = each.value.purpose
    }
  }

  spec {
    capacity = {
      storage = "${each.value.size}Gi"
    }
    
    access_modes                     = each.value.access_modes
    persistent_volume_reclaim_policy = each.value.reclaim_policy
    storage_class_name              = each.value.storage_class
    
    persistent_volume_source {
      csi {
        driver        = "linodebs.csi.linode.com"
        volume_handle = tostring(linode_volume.block_storage_volumes[each.key].id)
        fs_type       = each.value.filesystem
        
        volume_attributes = {
          "storage.kubernetes.io/csiProvisionerIdentity" = "linodebs.csi.linode.com"
          "linodebs.csi.linode.com/region"               = each.value.region
        }
      }
    }

    node_affinity {
      required {
        node_selector_term {
          match_expressions {
            key      = "topology.linodebs.csi.linode.com/region"
            operator = "In"
            values   = [each.value.region]
          }
        }
      }
    }
  }

  depends_on = [linode_volume.block_storage_volumes]
}

# Linode CSI Driver installation via Helm
resource "helm_release" "linode_csi_driver" {
  count = var.install_csi_driver ? 1 : 0

  name       = "linode-blockstorage-csi-driver"
  repository = "https://linode.github.io/linode-blockstorage-csi-driver"
  chart      = "linode-blockstorage-csi-driver"
  version    = var.csi_driver_version
  namespace  = var.csi_driver_namespace

  create_namespace = true

  values = [
    yamlencode({
      # API Token configuration
      apiToken = var.linode_token
      
      # Driver configuration
      driver = {
        image = {
          repository = "linode/linode-blockstorage-csi-driver"
          tag        = var.csi_driver_image_tag
        }
        
        # Resource configuration
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }
        
        # Node selector and tolerations
        nodeSelector = var.csi_driver_node_selector
        tolerations  = var.csi_driver_tolerations
      }
      
      # Controller configuration
      controller = {
        replicas = var.csi_controller_replicas
        
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }
      }
      
      # Node configuration
      node = {
        resources = {
          requests = {
            cpu    = "50m"
            memory = "64Mi"
          }
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
        }
      }
      
      # Storage class configuration
      storageClasses = {
        enabled = false  # We create our own storage classes
      }
      
      # Enable volume snapshots
      volumeSnapshotClasses = {
        enabled = var.enable_volume_snapshots
      }
      
      # Monitoring configuration
      serviceMonitor = {
        enabled = var.monitoring_enabled
        namespace = var.monitoring_namespace
      }
    })
  ]
}

# Volume Snapshot Classes for Linode
resource "kubernetes_manifest" "volume_snapshot_classes" {
  for_each = var.enable_volume_snapshots ? var.volume_snapshot_classes : {}

  manifest = {
    apiVersion = "snapshot.storage.k8s.io/v1"
    kind       = "VolumeSnapshotClass"
    
    metadata = {
      name = each.key
      labels = {
        "environment" = var.environment
        "managed-by"  = "terraform"
      }
    }
    
    driver = "linodebs.csi.linode.com"
    deletionPolicy = each.value.deletion_policy
    
    parameters = each.value.parameters
  }

  depends_on = [helm_release.linode_csi_driver]
}

# Backup policies using CronJobs
resource "kubernetes_cron_job_v1" "volume_backup_jobs" {
  for_each = var.backup_policies

  metadata {
    name      = "volume-backup-${each.key}"
    namespace = var.backup_namespace
    labels = {
      "app.kubernetes.io/name"      = "volume-backup"
      "app.kubernetes.io/component" = "backup-job"
      "environment"                 = var.environment
    }
  }

  spec {
    schedule                      = each.value.schedule
    timezone                     = each.value.timezone
    concurrency_policy           = "Forbid"
    successful_jobs_history_limit = 3
    failed_jobs_history_limit    = 1

    job_template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "volume-backup"
          "backup-policy"          = each.key
        }
      }

      spec {
        template {
          metadata {
            labels = {
              "app.kubernetes.io/name" = "volume-backup"
            }
          }

          spec {
            restart_policy = "OnFailure"

            container {
              name  = "backup"
              image = "linodecli/cli:latest"

              command = ["/bin/bash", "-c"]
              args = [
                templatefile("${path.module}/templates/backup-script.sh.tpl", {
                  volume_ids     = each.value.volume_ids
                  retention_days = each.value.retention_days
                  backup_prefix  = each.value.backup_prefix
                  region        = each.value.region
                })
              ]

              env {
                name = "LINODE_CLI_TOKEN"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret_v1.linode_credentials[0].metadata[0].name
                    key  = "token"
                  }
                }
              }

              resources {
                requests = {
                  cpu    = "100m"
                  memory = "128Mi"
                }
                limits = {
                  cpu    = "500m"
                  memory = "512Mi"
                }
              }
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_secret_v1.linode_credentials]
}

# Linode credentials secret
resource "kubernetes_secret_v1" "linode_credentials" {
  count = var.install_csi_driver || length(var.backup_policies) > 0 ? 1 : 0

  metadata {
    name      = "linode-credentials"
    namespace = var.csi_driver_namespace
  }

  data = {
    token = var.linode_token
  }

  type = "Opaque"
}

# Storage monitoring resources
resource "kubernetes_service_monitor" "storage_metrics" {
  count = var.monitoring_enabled ? 1 : 0

  metadata {
    name      = "linode-storage-metrics"
    namespace = var.monitoring_namespace
    labels = {
      "app.kubernetes.io/name"      = "linode-storage"
      "app.kubernetes.io/component" = "monitoring"
    }
  }

  spec {
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "linode-blockstorage-csi-driver"
      }
    }

    endpoints {
      port     = "metrics"
      interval = "30s"
      path     = "/metrics"
    }
  }

  depends_on = [helm_release.linode_csi_driver]
}

# Cost optimization - Volume resize automation
resource "kubernetes_cron_job_v1" "volume_optimization" {
  count = var.cost_optimization.enable_auto_resize ? 1 : 0

  metadata {
    name      = "volume-optimization"
    namespace = var.backup_namespace
    labels = {
      "app.kubernetes.io/name"      = "volume-optimization"
      "app.kubernetes.io/component" = "cost-optimization"
      "environment"                 = var.environment
    }
  }

  spec {
    schedule                      = var.cost_optimization.optimization_schedule
    concurrency_policy           = "Forbid"
    successful_jobs_history_limit = 1
    failed_jobs_history_limit    = 1

    job_template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "volume-optimization"
        }
      }

      spec {
        template {
          metadata {
            labels = {
              "app.kubernetes.io/name" = "volume-optimization"
            }
          }

          spec {
            restart_policy = "OnFailure"
            service_account_name = kubernetes_service_account_v1.volume_optimizer[0].metadata[0].name

            container {
              name  = "optimizer"
              image = "bitnami/kubectl:latest"

              command = ["/bin/bash", "-c"]
              args = [
                templatefile("${path.module}/templates/optimization-script.sh.tpl", {
                  utilization_threshold = var.cost_optimization.utilization_threshold
                  min_size_gb          = var.cost_optimization.min_size_gb
                  max_size_gb          = var.cost_optimization.max_size_gb
                })
              ]

              resources {
                requests = {
                  cpu    = "100m"
                  memory = "128Mi"
                }
                limits = {
                  cpu    = "200m"
                  memory = "256Mi"
                }
              }
            }
          }
        }
      }
    }
  }
}

# Service account for volume optimization
resource "kubernetes_service_account_v1" "volume_optimizer" {
  count = var.cost_optimization.enable_auto_resize ? 1 : 0

  metadata {
    name      = "volume-optimizer"
    namespace = var.backup_namespace
  }
}

# RBAC for volume optimization
resource "kubernetes_cluster_role_v1" "volume_optimizer" {
  count = var.cost_optimization.enable_auto_resize ? 1 : 0

  metadata {
    name = "volume-optimizer"
  }

  rule {
    api_groups = [""]
    resources  = ["persistentvolumes", "persistentvolumeclaims"]
    verbs      = ["get", "list", "watch", "patch", "update"]
  }

  rule {
    api_groups = ["storage.k8s.io"]
    resources  = ["storageclasses"]
    verbs      = ["get", "list"]
  }

  rule {
    api_groups = ["metrics.k8s.io"]
    resources  = ["pods", "nodes"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "volume_optimizer" {
  count = var.cost_optimization.enable_auto_resize ? 1 : 0

  metadata {
    name = "volume-optimizer"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.volume_optimizer[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.volume_optimizer[0].metadata[0].name
    namespace = var.backup_namespace
  }
}

