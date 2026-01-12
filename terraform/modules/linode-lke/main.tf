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
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

# Linode LKE Cluster
resource "linode_lke_cluster" "gateway_cluster" {
  label       = var.cluster_name
  k8s_version = var.kubernetes_version
  region      = var.region
  tags        = var.tags

  dynamic "pool" {
    for_each = var.node_pools
    content {
      type  = pool.value.type
      count = pool.value.count
      
      dynamic "autoscaler" {
        for_each = pool.value.autoscaler != null ? [pool.value.autoscaler] : []
        content {
          min = autoscaler.value.min
          max = autoscaler.value.max
        }
      }
    }
  }

  # Control plane access controls
  dynamic "control_plane" {
    for_each = var.control_plane_acl != null ? [var.control_plane_acl] : []
    content {
      high_availability = control_plane.value.high_availability
      
      dynamic "acl" {
        for_each = control_plane.value.acl != null ? [control_plane.value.acl] : []
        content {
          enabled = acl.value.enabled
          
          dynamic "addresses" {
            for_each = acl.value.addresses != null ? acl.value.addresses : []
            content {
              ipv4 = addresses.value.ipv4
              ipv6 = addresses.value.ipv6
            }
          }
        }
      }
    }
  }
}

# Gateway API CRDs
data "http" "gateway_api_crds" {
  url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml"
}

resource "kubernetes_manifest" "gateway_api_crds" {
  depends_on = [linode_lke_cluster.gateway_cluster]
  
  for_each = {
    for manifest in split("---", data.http.gateway_api_crds.response_body) :
    yamldecode(manifest).metadata.name => yamldecode(manifest)
    if can(yamldecode(manifest).metadata.name)
  }

  manifest = each.value
}

# Istio installation (if enabled)
resource "helm_release" "istio_base" {
  count      = var.install_istio ? 1 : 0
  depends_on = [linode_lke_cluster.gateway_cluster]

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

  # Linode-specific configurations
  set {
    name  = "pilot.env.EXTERNAL_ISTIOD"
    value = "false"
  }
}

# Istio Gateway for LoadBalancer
resource "helm_release" "istio_gateway" {
  count      = var.install_istio ? 1 : 0
  depends_on = [helm_release.istiod]

  name       = "istio-ingressgateway"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "gateway"
  namespace  = "istio-ingress"
  version    = var.istio_version

  create_namespace = true
  wait             = true
  timeout          = 300

  set {
    name  = "service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "service.annotations.service\\.beta\\.kubernetes\\.io/linode-loadbalancer-throttle"
    value = "4"
  }
}

# Monitoring stack (if enabled)
resource "kubernetes_namespace" "monitoring" {
  count = var.install_monitoring ? 1 : 0

  metadata {
    name = "monitoring"
    labels = {
      name = "monitoring"
    }
  }

  depends_on = [linode_lke_cluster.gateway_cluster]
}

resource "helm_release" "prometheus_stack" {
  count      = var.install_monitoring ? 1 : 0
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
    value = "linode-block-storage-retain"
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
    value = "linode-block-storage-retain"
  }

  set {
    name  = "grafana.persistence.size"
    value = var.grafana_storage_size
  }
}

