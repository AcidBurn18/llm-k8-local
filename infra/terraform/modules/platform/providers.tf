# ==============================================================================
# Terraform Providers Configuration
# ==============================================================================
#
# Key Architectural Decisions:
# 1. Provider Dependency & Ordering:
#    The Kind cluster resource (`kind_cluster.main`) boots the local Docker container
#    and updates ~/.kube/config with cluster credentials and a context named
#    "kind-${var.env_name}".
#    Terraform does not support explicit `depends_on` blocks inside `provider` blocks.
#    Therefore, all downstream resources (Kubernetes namespaces, Helm charts) explicitly
#    declare `depends_on = [kind_cluster.main]` to enforce strict topological ordering.
#    This guarantees the cluster is fully active and reachable before Kubernetes
#    and Helm clients attempt to interact with the API server.
#
# 2. Context Isolation:
#    Both `helm` and `kubernetes` providers target the dynamic context
#    `kind-${var.env_name}`. This allows multiple environments (e.g. dev, prod)
#    to be provisioned without polluting or overriding the default kubeconfig context.
# ==============================================================================

terraform {
  required_version = ">= 1.9"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "0.5.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.14.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.31.0"
    }
  }
}

provider "kind" {}

provider "helm" {
  kubernetes {
    config_path            = var.destroying_kind ? pathexpand("~/.kube/config") : null
    config_context         = var.destroying_kind ? "kind-${var.env_name}" : null
    host                   = var.destroying_kind ? null : kind_cluster.main.endpoint
    client_certificate     = var.destroying_kind ? null : kind_cluster.main.client_certificate
    client_key             = var.destroying_kind ? null : kind_cluster.main.client_key
    cluster_ca_certificate = var.destroying_kind ? null : kind_cluster.main.cluster_ca_certificate
  }
}

provider "kubernetes" {
  config_path            = var.destroying_kind ? pathexpand("~/.kube/config") : null
  config_context         = var.destroying_kind ? "kind-${var.env_name}" : null
  host                   = var.destroying_kind ? null : kind_cluster.main.endpoint
  client_certificate     = var.destroying_kind ? null : kind_cluster.main.client_certificate
  client_key             = var.destroying_kind ? null : kind_cluster.main.client_key
  cluster_ca_certificate = var.destroying_kind ? null : kind_cluster.main.cluster_ca_certificate
}
