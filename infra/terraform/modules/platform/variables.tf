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

variable "http_host_port" {
  type        = number
  description = "Host port mapped to the Kind ingress HTTP port"

  validation {
    condition     = var.http_host_port >= 1 && var.http_host_port <= 65535
    error_message = "http_host_port must be between 1 and 65535."
  }
}

variable "https_host_port" {
  type        = number
  description = "Host port mapped to the Kind ingress HTTPS port"

  validation {
    condition     = var.https_host_port >= 1 && var.https_host_port <= 65535
    error_message = "https_host_port must be between 1 and 65535."
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


variable "kind_ingress_trusted_proxy_cidr" {
  type        = string
  description = "Exact Kind Docker gateway address trusted to supply X-Forwarded-For in the local development cluster"
  default     = "172.20.0.1/32"
}

variable "destroying_kind" {
  type        = bool
  description = "Use kubeconfig instead of Kind resource credentials while destroying"
  default     = false
}
