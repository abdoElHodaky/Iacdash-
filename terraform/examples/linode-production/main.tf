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
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# Configure providers
provider "linode" {
  token = var.linode_token
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "lke${module.linode_cluster.cluster_id}-ctx"
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "lke${module.linode_cluster.cluster_id}-ctx"
  }
}

# Create production Linode LKE cluster
module "linode_cluster" {
  source = "../../modules/linode-lke"

  cluster_name       = var.cluster_name
  region             = var.region
  kubernetes_version = var.kubernetes_version

  node_pools = var.node_pools

  control_plane_acl = var.control_plane_acl
  tags              = var.tags

  # Service mesh configuration
  install_istio = var.install_istio
  istio_version = var.istio_version

  # Monitoring configuration
  install_monitoring       = var.install_monitoring
  prometheus_stack_version = var.prometheus_stack_version
  prometheus_retention     = var.prometheus_retention
  prometheus_storage_size  = var.prometheus_storage_size
  grafana_admin_password   = var.grafana_admin_password
  grafana_storage_size     = var.grafana_storage_size
}

# Configure kubectl context after cluster creation
resource "null_resource" "configure_kubectl" {
  depends_on = [module.linode_cluster]

  provisioner "local-exec" {
    command = <<-EOT
      echo "${module.linode_cluster.kubeconfig}" | base64 -d > ~/.kube/config-lke-${var.cluster_name}
      export KUBECONFIG=~/.kube/config-lke-${var.cluster_name}
      kubectl config rename-context lke${module.linode_cluster.cluster_id} lke${module.linode_cluster.cluster_id}-ctx
    EOT
  }

  triggers = {
    cluster_id = module.linode_cluster.cluster_id
  }
}
