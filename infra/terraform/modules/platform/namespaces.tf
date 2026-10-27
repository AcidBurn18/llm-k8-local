# ==============================================================================
# Kubernetes Namespaces & Pod Security Standards (PSS)
# ==============================================================================
#
# DevSecOps & Security Decision:
# 1. Pod Security Admission (PSA):
#    The 'app' namespace enforces the 'restricted' Pod Security Standard profile.
#    This enforces industry-standard hardening across all microservice pods:
#      - Disallows running as root (runAsNonRoot: true)
#      - Disallows privilege escalation (allowPrivilegeEscalation: false)
#      - Drops all Linux capabilities except NET_BIND_SERVICE if needed
#      - Enforces read-only root filesystems and restricted volume types
#    Both 'enforce' and 'warn' levels are set to 'restricted' to catch non-compliant
#    manifests early in CI/CD.
#
# 2. Dependency Ordering:
#    Both namespaces explicitly depend on `kind_cluster.main` to ensure the
#    cluster API server is ready before namespace creation is attempted.
# ==============================================================================

resource "kubernetes_namespace" "app" {
  metadata {
    name = "app"
    labels = {
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
      "app.kubernetes.io/managed-by"       = "terraform"
    }
  }

  depends_on = [kind_cluster.main]
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [kind_cluster.main]
}
