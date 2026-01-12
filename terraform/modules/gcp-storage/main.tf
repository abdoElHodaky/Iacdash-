terraform {
  required_version = ">= 1.6.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.10"
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

# GCP Persistent Disks
resource "google_compute_disk" "persistent_disks" {
  for_each = var.persistent_disks

  name = each.value.name
  type = each.value.disk_type
  zone = each.value.zone
  size = each.value.size

  # Performance optimization
  provisioned_iops = each.value.disk_type == "pd-extreme" ? each.value.provisioned_iops : null
  provisioned_throughput = each.value.disk_type == "hyperdisk-throughput" ? each.value.provisioned_throughput : null

  # Encryption
  disk_encryption_key {
    kms_key_name = each.value.kms_key_name
  }

  # Snapshot schedule
  dynamic "source_snapshot_schedule_policy" {
    for_each = each.value.snapshot_schedule != null ? [each.value.snapshot_schedule] : []
    content {
      schedule = source_snapshot_schedule_policy.value
    }
  }

  labels = merge(
    {
      environment = var.environment
      managed_by  = "terraform"
      purpose     = each.value.purpose
      tier        = each.value.performance_tier
    },
    each.value.additional_labels
  )
}

# Regional Persistent Disks for high availability
resource "google_compute_region_disk" "regional_persistent_disks" {
  for_each = var.regional_persistent_disks

  name   = each.value.name
  type   = each.value.disk_type
  region = each.value.region
  size   = each.value.size

  # Replication zones
  replica_zones = each.value.replica_zones

  # Performance optimization
  provisioned_iops = each.value.disk_type == "pd-extreme" ? each.value.provisioned_iops : null

  # Encryption
  disk_encryption_key {
    kms_key_name = each.value.kms_key_name
  }

  labels = merge(
    {
      environment = var.environment
      managed_by  = "terraform"
      purpose     = each.value.purpose
      tier        = each.value.performance_tier
      ha_enabled  = "true"
    },
    each.value.additional_labels
  )
}

# Filestore instances for shared file storage
resource "google_filestore_instance" "filestore_instances" {
  for_each = var.filestore_instances

  name     = each.value.name
  location = each.value.location
  tier     = each.value.tier

  file_shares {
    capacity_gb = each.value.capacity_gb
    name        = each.value.share_name

    # NFS export options
    dynamic "nfs_export_options" {
      for_each = each.value.nfs_export_options
      content {
        ip_ranges   = nfs_export_options.value.ip_ranges
        access_mode = nfs_export_options.value.access_mode
        squash_mode = nfs_export_options.value.squash_mode
        anon_uid    = nfs_export_options.value.anon_uid
        anon_gid    = nfs_export_options.value.anon_gid
      }
    }
  }

  networks {
    network = each.value.network
    modes   = each.value.network_modes
  }

  labels = merge(
    {
      environment = var.environment
      managed_by  = "terraform"
      purpose     = each.value.purpose
    },
    each.value.additional_labels
  )
}

# Storage Classes for different GCP storage types
resource "kubernetes_storage_class_v1" "gcp_storage_classes" {
  for_each = var.storage_classes

  metadata {
    name = each.key
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = each.value.is_default ? "true" : "false"
    }
    labels = {
      "storage.gcp.io/type"        = each.value.storage_type
      "storage.gcp.io/performance" = each.value.performance_tier
      "environment"                = var.environment
    }
  }

  storage_provisioner    = each.value.provisioner
  reclaim_policy        = each.value.reclaim_policy
  volume_binding_mode   = each.value.volume_binding_mode
  allow_volume_expansion = each.value.allow_volume_expansion

  parameters = merge(
    {
      type = each.value.disk_type
    },
    each.value.zone != null ? {
      zone = each.value.zone
    } : {},
    each.value.region != null ? {
      region = each.value.region
    } : {},
    each.value.replication_type != null ? {
      "replication-type" = each.value.replication_type
    } : {},
    each.value.provisioned_iops != null ? {
      "provisioned-iops-on-create" = tostring(each.value.provisioned_iops)
    } : {},
    each.value.provisioned_throughput != null ? {
      "provisioned-throughput-on-create" = tostring(each.value.provisioned_throughput)
    } : {},
    each.value.additional_parameters
  )
}

# Kubernetes Persistent Volumes for pre-provisioned GCP disks
resource "kubernetes_persistent_volume_v1" "gcp_pvs" {
  for_each = var.persistent_disks

  metadata {
    name = each.value.name
    labels = {
      "storage.gcp.io/disk-name" = google_compute_disk.persistent_disks[each.key].name
      "storage.gcp.io/zone"      = each.value.zone
      "environment"              = var.environment
      "purpose"                  = each.value.purpose
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
      gce_persistent_disk {
        pd_name   = google_compute_disk.persistent_disks[each.key].name
        fs_type   = each.value.filesystem
        partition = each.value.partition
      }
    }

    node_affinity {
      required {
        node_selector_term {
          match_expressions {
            key      = "topology.gke.io/zone"
            operator = "In"
            values   = [each.value.zone]
          }
        }
      }
    }
  }

  depends_on = [google_compute_disk.persistent_disks]
}

# Kubernetes Persistent Volumes for Filestore
resource "kubernetes_persistent_volume_v1" "filestore_pvs" {
  for_each = var.filestore_instances

  metadata {
    name = "${each.value.name}-pv"
    labels = {
      "storage.gcp.io/filestore-name" = google_filestore_instance.filestore_instances[each.key].name
      "storage.gcp.io/location"       = each.value.location
      "environment"                   = var.environment
      "purpose"                       = each.value.purpose
    }
  }

  spec {
    capacity = {
      storage = "${each.value.capacity_gb}Gi"
    }
    
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = each.value.reclaim_policy
    storage_class_name              = "filestore-${each.value.tier}"
    
    persistent_volume_source {
      nfs {
        server = google_filestore_instance.filestore_instances[each.key].networks[0].ip_addresses[0]
        path   = "/${each.value.share_name}"
      }
    }
  }

  depends_on = [google_filestore_instance.filestore_instances]
}

# Snapshot schedules for automated backups
resource "google_compute_resource_policy" "snapshot_schedules" {
  for_each = var.snapshot_schedules

  name   = each.value.name
  region = each.value.region

  snapshot_schedule_policy {
    schedule {
      daily_schedule {
        days_in_cycle = each.value.days_in_cycle
        start_time    = each.value.start_time
      }
    }

    retention_policy {
      max_retention_days    = each.value.max_retention_days
      on_source_disk_delete = each.value.on_source_disk_delete
    }

    snapshot_properties {
      labels = merge(
        {
          environment = var.environment
          managed_by  = "terraform"
          schedule    = each.key
        },
        each.value.snapshot_labels
      )
      storage_locations = each.value.storage_locations
      guest_flush       = each.value.guest_flush
    }
  }
}

# Attach snapshot schedules to disks
resource "google_compute_disk_resource_policy_attachment" "snapshot_attachments" {
  for_each = {
    for attachment in flatten([
      for disk_key, disk in var.persistent_disks : [
        for schedule_key in disk.snapshot_schedules : {
          disk_key     = disk_key
          schedule_key = schedule_key
          disk_name    = disk.name
          zone         = disk.zone
        }
      ]
    ]) : "${attachment.disk_key}-${attachment.schedule_key}" => attachment
  }

  name = google_compute_resource_policy.snapshot_schedules[each.value.schedule_key].name
  disk = google_compute_disk.persistent_disks[each.value.disk_key].name
  zone = each.value.zone

  depends_on = [
    google_compute_disk.persistent_disks,
    google_compute_resource_policy.snapshot_schedules
  ]
}

# Volume Snapshot Classes for GCP
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
    
    driver = "pd.csi.storage.gke.io"
    deletionPolicy = each.value.deletion_policy
    
    parameters = merge(
      {
        "storage-locations" = join(",", each.value.storage_locations)
      },
      each.value.additional_parameters
    )
  }
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
            service_account_name = kubernetes_service_account_v1.backup_service_account[0].metadata[0].name

            container {
              name  = "backup"
              image = "google/cloud-sdk:alpine"

              command = ["/bin/bash", "-c"]
              args = [
                templatefile("${path.module}/templates/backup-script.sh.tpl", {
                  project_id     = var.project_id
                  disk_names     = each.value.disk_names
                  retention_days = each.value.retention_days
                  backup_prefix  = each.value.backup_prefix
                  region        = each.value.region
                })
              ]

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

  depends_on = [kubernetes_service_account_v1.backup_service_account]
}

# Service account for backup operations
resource "kubernetes_service_account_v1" "backup_service_account" {
  count = length(var.backup_policies) > 0 ? 1 : 0

  metadata {
    name      = "gcp-backup-service-account"
    namespace = var.backup_namespace
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.backup_service_account[0].email
    }
  }
}

# GCP Service Account for backup operations
resource "google_service_account" "backup_service_account" {
  count = length(var.backup_policies) > 0 ? 1 : 0

  account_id   = "gcp-backup-sa"
  display_name = "GCP Backup Service Account"
  description  = "Service account for Kubernetes backup operations"
}

# IAM binding for backup service account
resource "google_project_iam_member" "backup_service_account_roles" {
  for_each = length(var.backup_policies) > 0 ? toset([
    "roles/compute.storageAdmin",
    "roles/compute.snapshotAdmin"
  ]) : toset([])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.backup_service_account[0].email}"
}

# Workload Identity binding
resource "google_service_account_iam_member" "workload_identity_binding" {
  count = length(var.backup_policies) > 0 ? 1 : 0

  service_account_id = google_service_account.backup_service_account[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.backup_namespace}/${kubernetes_service_account_v1.backup_service_account[0].metadata[0].name}]"
}

# Storage monitoring resources
resource "kubernetes_service_monitor" "storage_metrics" {
  count = var.monitoring_enabled ? 1 : 0

  metadata {
    name      = "gcp-storage-metrics"
    namespace = var.monitoring_namespace
    labels = {
      "app.kubernetes.io/name"      = "gcp-storage"
      "app.kubernetes.io/component" = "monitoring"
    }
  }

  spec {
    selector {
      match_labels = {
        "app" = "gcp-compute-persistent-disk-csi-driver"
      }
    }

    endpoints {
      port     = "metrics"
      interval = "30s"
      path     = "/metrics"
    }
  }
}

# Cost optimization - Disk type migration
resource "kubernetes_cron_job_v1" "disk_optimization" {
  count = var.cost_optimization.enable_disk_optimization ? 1 : 0

  metadata {
    name      = "disk-optimization"
    namespace = var.backup_namespace
    labels = {
      "app.kubernetes.io/name"      = "disk-optimization"
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
          "app.kubernetes.io/name" = "disk-optimization"
        }
      }

      spec {
        template {
          metadata {
            labels = {
              "app.kubernetes.io/name" = "disk-optimization"
            }
          }

          spec {
            restart_policy = "OnFailure"
            service_account_name = kubernetes_service_account_v1.optimization_service_account[0].metadata[0].name

            container {
              name  = "optimizer"
              image = "google/cloud-sdk:alpine"

              command = ["/bin/bash", "-c"]
              args = [
                templatefile("${path.module}/templates/optimization-script.sh.tpl", {
                  project_id           = var.project_id
                  utilization_threshold = var.cost_optimization.utilization_threshold
                  target_disk_type     = var.cost_optimization.target_disk_type
                })
              ]

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
}

# Service account for optimization operations
resource "kubernetes_service_account_v1" "optimization_service_account" {
  count = var.cost_optimization.enable_disk_optimization ? 1 : 0

  metadata {
    name      = "gcp-optimization-service-account"
    namespace = var.backup_namespace
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.optimization_service_account[0].email
    }
  }
}

# GCP Service Account for optimization operations
resource "google_service_account" "optimization_service_account" {
  count = var.cost_optimization.enable_disk_optimization ? 1 : 0

  account_id   = "gcp-optimization-sa"
  display_name = "GCP Optimization Service Account"
  description  = "Service account for disk optimization operations"
}

# IAM binding for optimization service account
resource "google_project_iam_member" "optimization_service_account_roles" {
  for_each = var.cost_optimization.enable_disk_optimization ? toset([
    "roles/compute.instanceAdmin",
    "roles/compute.storageAdmin"
  ]) : toset([])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.optimization_service_account[0].email}"
}

