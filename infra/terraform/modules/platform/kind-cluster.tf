# ==============================================================================
# Kind (Kubernetes-in-Docker) Cluster Definition
# ==============================================================================
#
# Design Decisions:
# 1. Port Forwarding:
#    Kind runs Kubernetes nodes inside Docker containers. To allow host traffic
#    (e.g., curl from macOS/Linux host) to reach the NGINX Ingress controller,
#    environment-specific host ports to the control-plane container.
# 2. Ingress Compatibility:
#    Combined with `controller.hostNetwork = true` in `helm-ingress.tf`, this
#    permits ingress traffic to hit `http://localhost` and `https://localhost`
#    without requiring manual `kubectl port-forward` commands.
# 3. Cluster Readiness:
#    `wait_for_ready = true` blocks Terraform execution until all control-plane
#    components (apiserver, etcd, scheduler, coredns) are healthy before
#    downstream namespace and Helm deployments begin.
# ==============================================================================

resource "kind_cluster" "main" {
  name           = var.env_name
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      extra_port_mappings {
        container_port = 80
        host_port      = var.http_host_port
        listen_address = "127.0.0.1"
        protocol       = "TCP"
      }

      extra_port_mappings {
        container_port = 443
        host_port      = var.https_host_port
        listen_address = "127.0.0.1"
        protocol       = "TCP"
      }
    }
  }
}
