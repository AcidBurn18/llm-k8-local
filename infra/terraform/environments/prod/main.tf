terraform {
  required_version = ">= 1.9"
}

module "platform" {
  source = "../../modules/platform"

  env_name         = var.env_name
  gateway_replicas = var.gateway_replicas
  http_host_port   = var.http_host_port
  https_host_port  = var.https_host_port
  destroying_kind  = var.destroying_kind
}
