# ============================================================================
# Kubernetes Metrics Server
# ============================================================================
# Required by the HPA and `kubectl top`. This is independent of Prometheus:
# Prometheus gathers application/monitoring metrics; Metrics Server exposes the
# resource metrics API used by Kubernetes autoscaling.
# ============================================================================

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.12.2" # Metrics Server 0.7.2 supports Kubernetes 1.27+
  namespace  = "kube-system"
  timeout    = 300
  wait       = true
  atomic     = true

  values = [file("${path.module}/metrics-server-values.yaml")]

  depends_on = [kind_cluster.main]
}
