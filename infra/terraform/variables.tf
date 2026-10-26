# ==============================================================================
# Terraform Input Variables
# ==============================================================================

variable "env_name" {
  type        = string
  description = "Environment name used as Kind cluster name"
  default     = "dev"
}

variable "gateway_replicas" {
  type        = number
  description = "Number of gateway pod replicas"
  default     = 1

  validation {
    condition     = var.gateway_replicas > 0
    error_message = "gateway_replicas must be at least 1."
  }
}

variable "enable_observability" {
  type        = bool
  description = "Install Prometheus Grafana Loki stack"
  default     = true
}

variable "ingress_nginx_version" {
  type        = string
  description = "Nginx ingress controller Helm chart version"
  default     = "4.10.1"
}

variable "kube_prometheus_version" {
  type        = string
  description = "kube-prometheus-stack Helm chart version"
  default     = "60.1.0"
}
