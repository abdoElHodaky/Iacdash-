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
  }
}

# Configure providers
provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${module.gke_cluster.cluster_endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = module.gke_cluster.cluster_ca_certificate
}

provider "helm" {
  kubernetes {
    host                   = "https://${module.gke_cluster.cluster_endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = module.gke_cluster.cluster_ca_certificate
  }
}

# Create VPC network for GKE cluster
resource "google_compute_network" "vpc" {
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false
  project                 = var.project_id
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${var.cluster_name}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id
  project       = var.project_id

  secondary_ip_range {
    range_name    = "gke-pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "gke-services"
    ip_cidr_range = var.services_cidr
  }
}

# Create production GKE cluster
module "gke_cluster" {
  source = "../../modules/gke-cluster"

  cluster_name = var.cluster_name
  project_id   = var.project_id
  location     = var.location

  # Network configuration
  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name

  # Kubernetes configuration
  kubernetes_version = var.kubernetes_version

  # Secondary ranges
  cluster_secondary_range_name  = "gke-pods"
  services_secondary_range_name = "gke-services"

  # Security configuration
  master_authorized_networks = var.master_authorized_networks
  private_cluster            = var.private_cluster
  private_endpoint           = var.private_endpoint
  master_ipv4_cidr_block     = var.master_ipv4_cidr_block

  # Maintenance configuration
  maintenance_start_time = var.maintenance_start_time

  # GKE-specific features
  enable_managed_prometheus = var.enable_managed_prometheus
  use_gke_gateway_addon     = var.use_gke_gateway_addon

  # Node pools
  node_pools = var.node_pools

  # Service mesh configuration
  install_istio = var.install_istio
  istio_version = var.istio_version

  # Monitoring configuration (only if not using managed Prometheus)
  install_monitoring       = var.install_monitoring
  prometheus_stack_version = var.prometheus_stack_version
  prometheus_retention     = var.prometheus_retention
  prometheus_storage_size  = var.prometheus_storage_size
  grafana_admin_password   = var.grafana_admin_password
  grafana_storage_size     = var.grafana_storage_size
}

# Create firewall rules for the cluster
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.cluster_name}-allow-internal"
  network = google_compute_network.vpc.name
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.subnet_cidr, var.pods_cidr, var.services_cidr]
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.cluster_name}-allow-ssh"
  network = google_compute_network.vpc.name
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.ssh_source_ranges
  target_tags   = ["gke-node"]
}

