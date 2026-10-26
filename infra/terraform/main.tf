# ==============================================================================
# DevSecOps Assessment - Main Terraform Architecture & Orchestration
# ==============================================================================
#
# Purpose:
#   This Terraform suite provisions and bootstraps a local DevSecOps development
#   and staging environment using Kind (Kubernetes-in-Docker) to host a demo
#   microservices-based LLM application stack.
#
# Environment Architecture & Workspace Strategy:
#   - We intentionally DO NOT use Terraform workspaces. In infrastructure engineering
#     and GitOps pipelines, workspaces can lead to shared state file blast-radii,
#     implicit context switching errors, and configuration drift.
#   - Instead, we isolate environments via explicit environment variable definition
#     files (e.g., environments/dev.tfvars, environments/prod.tfvars) paired with
#     dedicated local or remote backend state files:
#       * Dev:  terraform apply -var-file=environments/dev.tfvars -state=environments/dev.tfstate
#       * Prod: terraform apply -var-file=environments/prod.tfvars -state=environments/prod.tfstate
#   - Note: The project's root Makefile invokes:
#       make release ENV=dev
#     which runs terraform apply with -var-file=environments/$(ENV).tfvars.
#
# Resource Dependency Flow:
#   1. kind_cluster.main (kind-cluster.tf)
#      Creates Docker container hosting Kind control-plane and updates ~/.kube/config.
#   2. kubernetes_namespace.app & monitoring (namespaces.tf)
#      Enforces Kubernetes Pod Security Standards (Restricted profile) on app namespace.
#   3. helm_release.ingress_nginx (helm-ingress.tf)
#      Installs NGINX Ingress controller configured with hostNetwork and NodePort for Kind.
#   4. helm_release.monitoring (helm-prometheus.tf)
#      Installs Prometheus, Grafana, and Alertmanager stack for observability.
# ==============================================================================

locals {
  cluster_name = var.env_name
  kube_context = "kind-${var.env_name}"

  common_labels = {
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/part-of"    = "devsecops-llm-assessment"
    "environment"                  = var.env_name
  }
}
