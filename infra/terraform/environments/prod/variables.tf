variable "env_name" {
  type        = string
  description = "Environment and Kind cluster name"
  default     = "prod"
}

variable "gateway_replicas" {
  type        = number
  description = "Number of gateway replicas"
  default     = 2
}

variable "http_host_port" {
  type        = number
  description = "Host port mapped to the Kind ingress HTTP port"
  default     = 8080
}

variable "https_host_port" {
  type        = number
  description = "Host port mapped to the Kind ingress HTTPS port"
  default     = 8443
}


variable "destroying_kind" {
  type        = bool
  description = "Use kubeconfig instead of Kind resource credentials while destroying"
  default     = false
}
