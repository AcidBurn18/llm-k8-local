
output "cluster_name" {
  description = "The Kind cluster name"
  value       = kind_cluster.main.name
}

output "kubeconfig_context" {
  description = "The kubectl context name"
  value       = "kind-${var.env_name}"
}

output "ingress_nginx_version" {
  description = "The ingress version installed"
  value       = var.ingress_nginx_version
}

output "how_to_connect" {
  description = "A helpful command showing how to interact with the cluster via kubectl"
  value       = "kubectl cluster-info --context kind-${var.env_name}"
}
