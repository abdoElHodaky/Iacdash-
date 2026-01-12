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
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }
}

# Data sources for existing resources
data "openstack_blockstorage_volumetype_v3" "volume_types" {
  for_each = toset(var.volume_types)
  name     = each.value
}

# Storage Classes for different performance tiers
resource "kubernetes_storage_class_v1" "openstack_storage_classes" {
  for_each = var.storage_classes

  metadata {
    name = each.key
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = each.value.is_default ? "true" : "false"
    }
    labels = {
      "storage.openstack.io/type"        = each.value.volume_type
      "storage.openstack.io/performance" = each.value.performance_tier
      "environment"                      = var.environment
    }
  }

  storage_provisioner    = "cinder.csi.openstack.org"
  reclaim_policy        = each.value.reclaim_policy
  volume_binding_mode   = each.value.volume_binding_mode
  allow_volume_expansion = each.value.allow_volume_expansion

  parameters = merge(
    {
      type = each.value.volume_type
    },
    each.value.availability_zone != null ? {
      availability = each.value.availability_zone
    } : {},
    each.value.fstype != null ? {
      fsType = each.value.fstype
    } : {},
    each.value.additional_parameters
  )
}

# Persistent Volumes for pre-provisioned storage
resource "openstack_blockstorage_volume_v3" "persistent_volumes" {
  for_each = var.persistent_volumes

  name              = each.value.name
  description       = each.value.description
  size              = each.value.size
  volume_type       = each.value.volume_type
  availability_zone = each.value.availability_zone
  enable_online_resize = each.value.enable_online_resize

  metadata = merge(
    {
      environment = var.environment
      managed_by  = "terraform"
      purpose     = each.value.purpose
    },
    each.value.metadata
  )

  # Snapshot configuration
  dynamic "scheduler_hints" {
    for_each = each.value.scheduler_hints != null ? [each.value.scheduler_hints] : []
    content {
      local_to_instance = scheduler_hints.value.local_to_instance
      different_host    = scheduler_hints.value.different_host
      same_host         = scheduler_hints.value.same_host
    }
  }
}

# Kubernetes Persistent Volumes for pre-provisioned storage
resource "kubernetes_persistent_volume_v1" "openstack_pvs" {
  for_each = var.persistent_volumes

  metadata {
    name = each.value.name
    labels = {
      "storage.openstack.io/volume-id"   = openstack_blockstorage_volume_v3.persistent_volumes[each.key].id
      "storage.openstack.io/volume-type" = each.value.volume_type
      "environment"                      = var.environment
      "purpose"                          = each.value.purpose
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
        driver        = "cinder.csi.openstack.org"
        volume_handle = openstack_blockstorage_volume_v3.persistent_volumes[each.key].id
        fs_type       = each.value.fstype
        
        volume_attributes = {
          storage.kubernetes.io/csiProvisionerIdentity = "cinder.csi.openstack.org"
        }
      }
    }

    node_affinity {
      required {
        node_selector_term {
          match_expressions {
            key      = "topology.cinder.csi.openstack.org/zone"
            operator = "In"
            values   = [each.value.availability_zone]
          }
        }
      }
    }
  }

  depends_on = [openstack_blockstorage_volume_v3.persistent_volumes]
}

# Volume Snapshots for backup
resource "openstack_blockstorage_volume_v3" "volume_snapshots" {
  for_each = var.volume_snapshots

  name        = each.value.name
  description = each.value.description
  source_vol_id = each.value.source_volume_id
  size        = each.value.size

  metadata = {
    environment = var.environment
    snapshot_of = each.value.source_volume_id
    created_by  = "terraform"
    backup_type = each.value.backup_type
  }
}

# Cinder CSI Driver installation via Helm
resource "helm_release" "cinder_csi_driver" {
  count = var.install_csi_driver ? 1 : 0

  name       = "openstack-cinder-csi"
  repository = "https://kubernetes.github.io/cloud-provider-openstack"
  chart      = "openstack-cinder-csi"
  version    = var.csi_driver_version
  namespace  = var.csi_driver_namespace

  create_namespace = true

  values = [
    yamlencode({
      csi = {
        plugin = {
          image = {
            repository = "registry.k8s.io/provider-os/cinder-csi-plugin"
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
        }
        
        provisioner = {
          image = {
            repository = "registry.k8s.io/sig-storage/csi-provisioner"
            tag        = "v3.6.0"
          }
          
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
        
        attacher = {
          image = {
            repository = "registry.k8s.io/sig-storage/csi-attacher"
            tag        = "v4.4.0"
          }
        }
        
        resizer = {
          image = {
            repository = "registry.k8s.io/sig-storage/csi-resizer"
            tag        = "v1.9.0"
          }
        }
        
        snapshotter = {
          image = {
            repository = "registry.k8s.io/sig-storage/csi-snapshotter"
            tag        = "v6.3.0"
          }
        }
      }
      
      # OpenStack configuration
      openstack = {
        authUrl    = var.openstack_auth_url
        region     = var.openstack_region
        projectId  = var.openstack_project_id
        domainId   = var.openstack_domain_id
        
        # Use secret for credentials
        secretName = kubernetes_secret_v1.openstack_credentials[0].metadata[0].name
      }
      
      # Storage class configuration
      storageClass = {
        enabled = false  # We create our own storage classes
      }
      
      # Node selector for CSI driver pods
      nodeSelector = var.csi_driver_node_selector
      
      # Tolerations for CSI driver pods
      tolerations = var.csi_driver_tolerations
    })
  ]

  depends_on = [kubernetes_secret_v1.openstack_credentials]
}

# OpenStack credentials secret for CSI driver
resource "kubernetes_secret_v1" "openstack_credentials" {
  count = var.install_csi_driver ? 1 : 0

  metadata {
    name      = "cloud-config"
    namespace = var.csi_driver_namespace
  }

  data = {
    "cloud.conf" = templatefile("${path.module}/templates/cloud.conf.tpl", {
      auth_url    = var.openstack_auth_url
      region      = var.openstack_region
      project_id  = var.openstack_project_id
      domain_id   = var.openstack_domain_id
      username    = var.openstack_username
      password    = var.openstack_password
    })
  }

  type = "Opaque"
}

# Volume Snapshot Classes
resource "kubernetes_manifest" "volume_snapshot_classes" {
  for_each = var.volume_snapshot_classes

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
    
    driver = "cinder.csi.openstack.org"
    deletionPolicy = each.value.deletion_policy
    
    parameters = each.value.parameters
  }

  depends_on = [helm_release.cinder_csi_driver]
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
              image = "openstacktools/openstack-client:latest"

              command = ["/bin/bash", "-c"]
              args = [
                templatefile("${path.module}/templates/backup-script.sh.tpl", {
                  volume_ids     = each.value.volume_ids
                  retention_days = each.value.retention_days
                  backup_prefix  = each.value.backup_prefix
                })
              ]

              env_from {
                secret_ref {
                  name = kubernetes_secret_v1.openstack_credentials[0].metadata[0].name
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

  depends_on = [kubernetes_secret_v1.openstack_credentials]
}

