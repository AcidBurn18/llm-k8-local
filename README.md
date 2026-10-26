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

See [docs/architecture.md](docs/architecture.md) for the full Mermaid diagram.

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Docker Desktop | latest | https://www.docker.com/products/docker-desktop |
| Kind | v0.23+ | `brew install kind` |
| kubectl | v1.29+ | `brew install kubectl` |
| Helm | v3.15+ | `brew install helm` |
| Terraform | v1.8+ | `brew install hashicorp/tap/terraform` |
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

This will:
1. Lint + test + build all images
2. Generate SBOMs and scan for vulnerabilities
3. Load images into the Kind cluster
4. Run `terraform apply` to provision the cluster and install Helm charts
5. Apply all Kubernetes manifests

## Manual Step-by-Step

See [docs/runbook.md](docs/runbook.md) for full setup, deploy, verify, rollback, and teardown steps.

## Endpoints (after deployment)

| Endpoint | Description |
|----------|-------------|
| `GET  https://llm-app.local/healthz` | Gateway health check |
| `GET  https://llm-app.local/api/v1/items` | List all catalog items |
| `GET  https://llm-app.local/api/v1/items/:id` | Get one item |
| `POST https://llm-app.local/api/v1/ask` | Ask a question (reaches LLM) |

### Example ask request

```bash
curl -k -X POST https://llm-app.local/api/v1/ask \
  -H "Content-Type: application/json" \
  -d '{"question": "Summarize this item", "item_id": "item-1"}'
```

## Environments

| Environment | Terraform vars |
|-------------|----------------|
| dev | `infra/terraform/environments/dev.tfvars` |
| prod | `infra/terraform/environments/prod.tfvars` |

```bash
# Deploy to prod
make release ENV=prod

# Destroy dev
make destroy ENV=dev
```

## Design & Trade-offs

See [docs/security-decisions.md](docs/security-decisions.md) for security decisions.  
See the Known Limitations section at the bottom of this file.

## Known Limitations

- TLS uses a self-signed cert via mkcert (not a real CA)
- LLM inference is slow on CPU (~10–30s per response) — expected with 0.5B model
- No real unit tests for services (stubs only due to time)
- Image signing is documented but not implemented (would use `cosign` in production)
- Single-node Kind cluster — PodDisruptionBudget is demonstrative only

## AI Usage

See [AI_USAGE.md](AI_USAGE.md).
