# Kind Cluster Module

This Terraform module creates a local Kubernetes cluster using Kind (Kubernetes in Docker).

## Usage

```hcl
module "kind_cluster" {
  source = "./modules/kind-cluster"
  
  cluster_name = "my-cluster"
  # Add other variables as needed
}
```

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
