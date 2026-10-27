# ==============================================================================
# NGINX Ingress Controller Helm Release
# ==============================================================================
#
# Architectural Decision:
# 1. Kind Host Port Routing:
#    In a local Kind environment, there is no native cloud LoadBalancer provider.
#    By setting `controller.hostNetwork = true` and `controller.service.type = NodePort`,
#    the ingress-nginx controller binds directly to ports 80 and 443 of the Kind
#    node container. Combined with `extra_port_mappings` on `kind_cluster.main`,
#    traffic sent to localhost:80/localhost:443 seamlessly routes directly into
#    the cluster ingress rules.
#
# 2. Namespace Creation:
#    `create_namespace = true` isolates the ingress controller in its own
#    `ingress-nginx` namespace while avoiding boilerplate namespace definitions.
#
# 3. Cluster Dependency:
#    `depends_on = [kind_cluster.main]` prevents Helm from attempting chart
#    installations until the Kind cluster is operational.
# ==============================================================================

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.ingress_nginx_version
  namespace        = "ingress-nginx"
  create_namespace = true
  timeout          = 300

  set {
    name  = "controller.hostNetwork"
    value = "true"
  }

  set {
    name  = "controller.service.type"
    value = "NodePort"
  }

  # Kind's host port mapping reaches NGINX through this Docker bridge gateway.
  # Trust forwarded client IPs only from that exact address; the Kind host ports
  # are bound to localhost in kind-cluster.tf.
  set {
    name  = "controller.config.enable-real-ip"
    value = "true"
  }

  set {
    name  = "controller.config.use-forwarded-headers"
    value = "true"
  }

  set {
    name  = "controller.config.proxy-real-ip-cidr"
    value = var.kind_ingress_trusted_proxy_cidr
  }

  depends_on = [kind_cluster.main]
}
