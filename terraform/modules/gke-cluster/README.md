# GKE Cluster Module

This Terraform module creates a Google Kubernetes Engine (GKE) cluster.

## Usage

```hcl
module "gke_cluster" {
  source = "./modules/gke-cluster"
  
  cluster_name = "my-gke-cluster"
  # Add other variables as needed
}
```

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
