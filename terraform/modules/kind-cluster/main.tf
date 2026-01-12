terraform {
  required_version = ">= 1.6.0"
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.4"
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

# KinD cluster configuration
resource "kind_cluster" "default" {
  name           = var.cluster_name
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      kubeadm_config_patches = [
        "kind: InitConfiguration\nnodeRegistration:\n  kubeletExtraArgs:\n    node-labels: \"ingress-ready=true\"\n"
      ]

      extra_port_mappings {
        container_port = 80
        host_port      = 80
      }
      extra_port_mappings {
        container_port = 443
        host_port      = 443
      }
    }

    dynamic "node" {
      for_each = range(var.worker_nodes)
      content {
        role = "worker"
      }
    }
  }
}

# Gateway API CRDs
data "http" "gateway_api_crds" {
  url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml"
}

resource "kubernetes_manifest" "gateway_api_crds" {
  depends_on = [kind_cluster.default]

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
  depends_on = [kind_cluster.default]

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

  depends_on = [kind_cluster.default]
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
    value = "7d"
  }

  set {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }
}

