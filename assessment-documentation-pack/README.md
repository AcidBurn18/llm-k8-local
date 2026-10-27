# LLM App — DevSecOps & MLOps Assessment

## Architecture

```
Browser / curl
      │ HTTPS :443
      ▼
Nginx Ingress (TLS)
      │
      ▼
API Gateway  ──── GET /api/v1/items ────► Catalog Service
      │                                        (in-memory items)
      └──── POST /api/v1/ask ──────────► Assistant Service
                                              │
                                    GET /items/:id  POST /generate
                                              │           │
                                         Catalog       LLM Inference
                                                    (Qwen2.5-0.5B)
                                                          │
                                                   PersistentVolume
                                                   (model weights)
```

See [the architecture](docs/architecture.md) for the service diagram and request flow. For a hands-on tour of the Python services, code-to-cluster workflow, logs, and debugging, use [the practical guide](docs/hands-on-code-and-deployment.md).

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Docker Desktop | latest | https://www.docker.com/products/docker-desktop |
| Kind | v0.23+ | `brew install kind` |
| kubectl | v1.29+ | `brew install kubectl` |
| Helm | v3.15+ | `brew install helm` |
| Terraform | v1.9+ | `brew install hashicorp/tap/terraform` |
| trivy | latest | `brew install aquasecurity/trivy/trivy` |
| syft | latest | `brew install syft` |
| mkcert | latest | `brew install mkcert && mkcert -install` |
| Python | 3.11 | `brew install python@3.11` |
| jq | latest | `brew install jq` |

**Minimum hardware**: 4 CPU cores, 8 GB RAM, 20 GB free disk.

## Quick Start (one command)

```bash
make release ENV=dev
```

This lints and tests the services, builds four images, writes SBOMs, scans the images, shows the Terraform plan, loads images into Kind, and applies the Kubernetes manifests. Before infrastructure changes, type `apply` at the Makefile prompt and then confirm Terraform's own yes/no prompt. The release waits for Metrics Server and the application deployments.

To proceed despite HIGH/CRITICAL findings, explicitly override the scan gate:

```bash
make release ENV=dev ALLOW_HIGH_VULNS=true
```

This still runs Trivy and writes reports; it only allows vulnerability findings through the severity gate. Scanner errors still fail the release. Review the reports before sharing the images.

## Documentation

- [Runbook](docs/runbook.md) — prerequisites, deployment, verification, operations, teardown, troubleshooting
- [Quick run guide](docs/how-to-run.md) — shortest path from a fresh checkout to a live request
- [Architecture](docs/architecture.md) — components and request flow
- [Design decisions and trade-offs](docs/decisions-and-assumptions.md)
- [Security decisions](docs/security-decisions.md)
- [Cloud portability note](docs/cloud-portability.md)
- [Model delivery](model/README.md)
- [SBOM and vulnerability scan files](docs/sbom-and-scans/README.md)
- [Assessment completion and known gaps](docs/submission-status.md)
- [AI usage disclosure](AI_USAGE.md)
- [Hands-on code and deployment guide](docs/hands-on-code-and-deployment.md)

## Endpoints (after deployment)

| Endpoint | Description |
|----------|-------------|
| `GET  https://llm-app.local/healthz` | Gateway health check (`dev`) |
| `GET  https://llm-app.local/api/v1/items` | List all catalog items (`dev`) |
| `GET  https://llm-app.local/api/v1/items/:id` | Get one item (`dev`) |
| `POST https://llm-app.local/api/v1/ask` | Ask a question (reaches LLM, `dev`) |

The `prod` Kind cluster maps ingress to ports `8080`/`8443`, so use `https://llm-app.local:8443` for prod. The same `llm-app.local` DNS/hosts entry works for both; the port selects the cluster. `make verify ENV=prod` automatically checks the prod URL.

### Example ask request

```bash
curl -k -X POST https://llm-app.local/api/v1/ask \
  -H "Content-Type: application/json" \
  -d '{"question": "Summarize this item", "item_id": "item-1"}'
```

## Environments

| Environment | Terraform root and state |
|-------------|-------------------------|
| dev | `infra/terraform/environments/dev/` |
| prod | `infra/terraform/environments/prod/` |

Each environment has an independent Terraform root and local state in its own directory. Both roots call the shared module in `infra/terraform/modules/platform`; `make infra ENV=dev` and `make infra ENV=prod` select the corresponding root. The `prod` configuration is an isolated assignment example; it has not been deployed or verified as production infrastructure.

For the provider lifecycle, kubeconfig contexts, destroy behavior, and the `kind-dev` context error, see [the Terraform and kubeconfig guide](docs/terraform-kubeconfig-explained.md).

## Design & Trade-offs

See [design and trade-offs](docs/decisions-and-assumptions.md) and [security decisions](docs/security-decisions.md).

## Known Limitations

- `make release` configures the Ingress for TLS, but it does not create the referenced `tls-secret`; the local mkcert setup must be completed separately. The smoke test uses `curl -k`, so it checks HTTPS routing but not browser trust of the certificate.
- The Terraform roots and state are separate for `dev` and `prod`. Only `dev` was previously deployed and tested;
- Application logs are available with `kubectl logs`; a central log backend is not installed.
- Prometheus and Grafana are installed. An alert rule is present, but alert firing and notification to an incident channel were not tested or configured.
- The daily model CronJob is defined, but the release script does not wait for or manually trigger it as a verification step.
- The gateway HPA and Metrics Server work, but a load-driven scale-up was not demonstrated.
- Unit tests cover the gateway, catalog, and assistant service behavior; there is no unit-test file for the LLM service. The live smoke suite did exercise an end-to-end request that reached the LLM, but it does not cover every deployment or infrastructure failure mode.
- Image signing is documented as a next step and is not implemented. The Kind cluster is single-node, so the PDB is demonstrative.

## Verification

On the last local release, Ruff passed, 27 unit tests passed, Terraform created the dev environment, the model download Job completed, and all six smoke checks passed. The smoke suite included an LLM request and allowed/blocked forwarded-IP cases. `kubectl top` returned metrics for the node and app pods. See [the completion matrix](docs/submission-status.md) for items that remain unverified or incomplete.
