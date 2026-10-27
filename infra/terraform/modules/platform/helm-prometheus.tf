# ==============================================================================
# Prometheus & Grafana Observability Stack (kube-prometheus-stack)
# ==============================================================================
#
# Design & Operational Decisions:
# 1. Conditional Observability:
#    `count = var.enable_observability ? 1 : 0` allows spinning up a lightweight
#    cluster for rapid CI unit runs or deploying the complete observability stack
#    when benchmarking, testing alerts, or evaluating SLOs/metrics.
#
# 2. Cross-Namespace ServiceMonitor Discovery:
#    `prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues = false`
#    is critical. By default, Prometheus Operator only scrapes ServiceMonitors created
#    by this Helm chart. Setting this to false enables Prometheus to discover and
#    scrape custom ServiceMonitors deployed alongside the LLM microservices in the
#    `app` namespace.
#
# 3. Fixed NodePort for Grafana:
#    Configuring NodePort 32000 allows direct and predictable browser access
#    to Grafana metrics dashboards.
#
# 4. Dependency Management:
#    Explicitly references `kubernetes_namespace.monitoring` to ensure the target
#    namespace is created and labeled before CRD and operator rollout starts.
# ==============================================================================

resource "helm_release" "monitoring" {
  count      = var.enable_observability ? 1 : 0
  name       = "monitoring"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.kube_prometheus_version
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  timeout    = 600

  set {
    name  = "grafana.service.type"
    value = "NodePort"
  }

  set {
    name  = "grafana.service.nodePort"
    value = "32000"
  }

  set {
    name  = "grafana.adminPassword"
    value = "admin123"
  }

  set {
    name  = "prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues"
    value = "false"
  }

  depends_on = [kubernetes_namespace.monitoring]
}
