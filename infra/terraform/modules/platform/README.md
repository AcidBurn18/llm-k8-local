# Shared Terraform platform module

This module provisions the Kind cluster and its Kubernetes namespaces, ingress, Metrics Server, and monitoring stack. The independent roots in `infra/terraform/environments/dev` and `infra/terraform/environments/prod` call this module and keep state in their own directories.

Regenerate this reference from the repository root with:

```bash
terraform-docs -c infra/terraform/.terraform-docs.yml infra/terraform/modules/platform
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | 2.14.0 |
| <a name="requirement_kind"></a> [kind](#requirement\_kind) | 0.5.1 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | 2.31.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_helm"></a> [helm](#provider\_helm) | 2.14.0 |
| <a name="provider_kind"></a> [kind](#provider\_kind) | 0.5.1 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | 2.31.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [helm_release.ingress_nginx](https://registry.terraform.io/providers/hashicorp/helm/2.14.0/docs/resources/release) | resource |
| [helm_release.metrics_server](https://registry.terraform.io/providers/hashicorp/helm/2.14.0/docs/resources/release) | resource |
| [helm_release.monitoring](https://registry.terraform.io/providers/hashicorp/helm/2.14.0/docs/resources/release) | resource |
| [kind_cluster.main](https://registry.terraform.io/providers/tehcyx/kind/0.5.1/docs/resources/cluster) | resource |
| [kubernetes_namespace.app](https://registry.terraform.io/providers/hashicorp/kubernetes/2.31.0/docs/resources/namespace) | resource |
| [kubernetes_namespace.monitoring](https://registry.terraform.io/providers/hashicorp/kubernetes/2.31.0/docs/resources/namespace) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_destroying_kind"></a> [destroying\_kind](#input\_destroying\_kind) | Use kubeconfig instead of Kind resource credentials while destroying | `bool` | `false` | no |
| <a name="input_enable_observability"></a> [enable\_observability](#input\_enable\_observability) | Install the local Prometheus, Grafana, Alertmanager, Loki, and Alloy observability stack | `bool` | `true` | no |
| <a name="input_env_name"></a> [env\_name](#input\_env\_name) | Environment name used as Kind cluster name | `string` | `"dev"` | no |
| <a name="input_gateway_replicas"></a> [gateway\_replicas](#input\_gateway\_replicas) | Number of gateway pod replicas | `number` | `1` | no |
| <a name="input_http_host_port"></a> [http\_host\_port](#input\_http\_host\_port) | Host port mapped to the Kind ingress HTTP port | `number` | n/a | yes |
| <a name="input_https_host_port"></a> [https\_host\_port](#input\_https\_host\_port) | Host port mapped to the Kind ingress HTTPS port | `number` | n/a | yes |
| <a name="input_ingress_nginx_version"></a> [ingress\_nginx\_version](#input\_ingress\_nginx\_version) | Nginx ingress controller Helm chart version | `string` | `"4.10.1"` | no |
| <a name="input_kind_ingress_trusted_proxy_cidr"></a> [kind\_ingress\_trusted\_proxy\_cidr](#input\_kind\_ingress\_trusted\_proxy\_cidr) | Exact Kind Docker gateway address trusted to supply X-Forwarded-For in the local development cluster | `string` | `"172.20.0.1/32"` | no |
| <a name="input_kube_prometheus_version"></a> [kube\_prometheus\_version](#input\_kube\_prometheus\_version) | kube-prometheus-stack Helm chart version | `string` | `"60.1.0"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | The Kind cluster name |
| <a name="output_how_to_connect"></a> [how\_to\_connect](#output\_how\_to\_connect) | A helpful command showing how to interact with the cluster via kubectl |
| <a name="output_ingress_nginx_version"></a> [ingress\_nginx\_version](#output\_ingress\_nginx\_version) | The ingress version installed |
| <a name="output_kubeconfig_context"></a> [kubeconfig\_context](#output\_kubeconfig\_context) | The kubectl context name |
<!-- END_TF_DOCS -->
