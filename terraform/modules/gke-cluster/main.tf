terraform {
  required_version = ">= 1.6.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

# GKE Cluster
resource "google_container_cluster" "gateway_cluster" {
  name     = var.cluster_name
  location = var.location
  project  = var.project_id

  # Network configuration
  network    = var.network
  subnetwork = var.subnetwork

  # Remove default node pool
  remove_default_node_pool = true
  initial_node_count       = 1

  # Cluster configuration
  min_master_version = var.kubernetes_version

  # Gateway API addon
  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  # Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Network policy
  network_policy {
    enabled = true
  }

  # IP allocation policy for VPC-native cluster
  ip_allocation_policy {
    cluster_secondary_range_name  = var.cluster_secondary_range_name
    services_secondary_range_name = var.services_secondary_range_name
  }

  # Master authorized networks
  dynamic "master_authorized_networks_config" {
    for_each = var.master_authorized_networks != null ? [var.master_authorized_networks] : []
    content {
      gcp_public_cidrs_access_enabled = master_authorized_networks_config.value.gcp_public_cidrs_access_enabled

      dynamic "cidr_blocks" {
        for_each = master_authorized_networks_config.value.cidr_blocks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }

  # Private cluster configuration
  dynamic "private_cluster_config" {
    for_each = var.private_cluster ? [1] : []
    content {
      enable_private_nodes    = true
      enable_private_endpoint = var.private_endpoint
      master_ipv4_cidr_block  = var.master_ipv4_cidr_block
    }
  }

  # Addons
  addons_config {
    http_load_balancing {
      disabled = false
    }

    horizontal_pod_autoscaling {
      disabled = false
    }

    network_policy_config {
      disabled = false
    }

    dns_cache_config {
      enabled = true
    }
  }

  # Maintenance policy
  maintenance_policy {
    daily_maintenance_window {
      start_time = var.maintenance_start_time
    }
  }

  # Logging and monitoring
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]

    managed_prometheus {
      enabled = var.enable_managed_prometheus
    }
  }
}

# Node pools
resource "google_container_node_pool" "primary_nodes" {
  for_each = var.node_pools

  name     = each.key
  location = var.location
  cluster  = google_container_cluster.gateway_cluster.name
  project  = var.project_id

  node_count = each.value.node_count

  # Autoscaling
  dynamic "autoscaling" {
    for_each = each.value.autoscaling != null ? [each.value.autoscaling] : []
    content {
      min_node_count = autoscaling.value.min_node_count
      max_node_count = autoscaling.value.max_node_count
    }
  }

  # Node configuration
  node_config {
    preemptible  = each.value.preemptible
    machine_type = each.value.machine_type
    disk_size_gb = each.value.disk_size_gb
    disk_type    = each.value.disk_type

    # Google service account
    service_account = google_service_account.gke_node_sa.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    # Workload Identity
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Labels and tags
    labels = merge(
      {
        cluster = var.cluster_name
        pool    = each.key
      },
      each.value.labels
    )

    tags = each.value.tags

    # Shielded instance configuration
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  # Upgrade settings
  upgrade_settings {
    max_surge       = each.value.max_surge
    max_unavailable = each.value.max_unavailable
  }

  # Management
  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# Service account for GKE nodes
resource "google_service_account" "gke_node_sa" {
  account_id   = "${var.cluster_name}-node-sa"
  display_name = "GKE Node Service Account for ${var.cluster_name}"
  project      = var.project_id
}

# IAM bindings for node service account
resource "google_project_iam_member" "gke_node_sa_bindings" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}

# Gateway API CRDs (if not using GKE Gateway addon)
data "http" "gateway_api_crds" {
  count = var.use_gke_gateway_addon ? 0 : 1
  url   = "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml"
}

resource "kubernetes_manifest" "gateway_api_crds" {
  depends_on = [google_container_cluster.gateway_cluster]

  for_each = var.use_gke_gateway_addon ? {} : {
    for manifest in split("---", data.http.gateway_api_crds[0].response_body) :
    yamldecode(manifest).metadata.name => yamldecode(manifest)
    if can(yamldecode(manifest).metadata.name)
  }

  manifest = each.value
}

# Istio installation (if enabled)
resource "helm_release" "istio_base" {
  count      = var.install_istio ? 1 : 0
  depends_on = [google_container_cluster.gateway_cluster]

  name       = "istio-base"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "base"
  namespace  = "istio-system"
  version    = var.istio_version

  create_namespace = true
  wait             = true
  timeout          = 300
}

resource "helm_release" "istiod" {
  count      = var.install_istio ? 1 : 0
  depends_on = [helm_release.istio_base]

  name       = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "istiod"
  namespace  = "istio-system"
  version    = var.istio_version

  wait    = true
  timeout = 300

  set {
    name  = "global.meshID"
    value = "mesh1"
  }

  set {
    name  = "global.multiCluster.clusterName"
    value = var.cluster_name
  }

  set {
    name  = "global.network"
    value = "network1"
  }

  # GKE-specific configurations
  set {
    name  = "pilot.env.EXTERNAL_ISTIOD"
    value = "false"
  }
}

# Monitoring stack (if enabled and not using GKE managed)
resource "kubernetes_namespace" "monitoring" {
  count = var.install_monitoring && !var.enable_managed_prometheus ? 1 : 0

  metadata {
    name = "monitoring"
    labels = {
      name = "monitoring"
    }
  }

  depends_on = [google_container_cluster.gateway_cluster]
}

resource "helm_release" "prometheus_stack" {
  count      = var.install_monitoring && !var.enable_managed_prometheus ? 1 : 0
  depends_on = [kubernetes_namespace.monitoring]

  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = "monitoring"
  version    = var.prometheus_stack_version

  wait    = true
  timeout = 600

  set {
    name  = "prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues"
    value = "false"
  }

  set {
    name  = "prometheus.prometheusSpec.retention"
    value = var.prometheus_retention
  }

  set {
    name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName"
    value = "standard-rwo"
  }

  set {
    name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage"
    value = var.prometheus_storage_size
  }

  set {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }

  set {
    name  = "grafana.persistence.enabled"
    value = "true"
  }

  set {
    name  = "grafana.persistence.storageClassName"
    value = "standard-rwo"
  }

  set {
    name  = "grafana.persistence.size"
    value = var.grafana_storage_size
  }
}
