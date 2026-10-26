# Decisions & Assumptions

> This document records every non-obvious choice made during the build, the reasoning behind it,
> and what we assumed when the spec left something open.
> Understanding this document is essential for the live review discussion.

---

## 1. Docker Base Image: Tag vs Digest

### The Decision
We use `FROM python:3.11-slim` **by tag** in the Dockerfiles right now, with a `# TODO: pin by digest` comment.

### Why Digest Pinning Matters
When you write `FROM python:3.11-slim`, Docker resolves the tag to whichever image SHA the registry is currently serving. If a maintainer pushes a new image under the same tag (for example to patch a CVE), your next build silently uses a different base — without you changing a single line of code. This is a supply-chain risk.

Pinning by digest (`FROM python:3.11-slim@sha256:abc123...`) means the build is always reproducible: the exact same bytes, always.

### How to Get the Digest
```bash
# Pull the image first
docker pull python:3.11-slim

# Get its digest
docker inspect python:3.11-slim --format='{{index .RepoDigests 0}}'
# Output example: python@sha256:a1b2c3d4e5f6...

# Then update your Dockerfile FROM line:
# FROM python:3.11-slim@sha256:a1b2c3d4e5f6...
```

### Why We Didn't Do It Right Away
The digest changes every time the upstream image is updated (security patches, etc.). During rapid development, pinning too early means you'd constantly be chasing stale digests. **The right workflow is**: finalize all Dockerfiles → get clean `trivy` scan results → then pin digests → commit. We document this as a "before release" step.

### Production Approach
In a real CI/CD pipeline you would:
1. Use a tool like `docker-lock` or `crane digest` to automatically resolve and pin digests.
2. Set up Dependabot or Renovate to open PRs when upstream digests change.

---

## 2. Model Weights: Baked Into Image vs Downloaded Separately

### The Decision
Model weights live in a **PersistentVolume**, downloaded by a Kubernetes Job (or init-container). They are **never** baked into the container image.

### Why Not Bake Into Image
| Problem | Impact |
|---------|--------|
| Qwen2.5-0.5B weights are ~1 GB | Image push/pull takes minutes; every `docker build` re-downloads weights |
| Weights are not our code | They have a separate license (Apache 2.0) and should be traceable |
| Can't patch the app without re-downloading weights | Slow and wasteful CI |
| Leaks model into image layers | Makes image scanning and SBOM noisier |

### Why a Kubernetes Job (not Init Container for every pod restart)
- The Job runs **once**, populates the PVC, and exits.
- The PVC persists across pod restarts — no re-download needed unless explicitly re-run.
- An init-container on every LLM pod would re-download on every pod restart, which is slow and hits HuggingFace rate limits.
- **Trade-off**: If the PVC is deleted, you must manually re-run the Job. This is documented in the runbook.

### Why HuggingFace Hub (not direct HTTP)
`snapshot_download()` from `huggingface_hub` handles:
- Resumable downloads (picks up where it left off if interrupted)
- File-level checksums (sha256 per file, verified automatically)
- Parallel file downloads for multi-file models

We add an **additional** whole-file SHA-256 check after download as an explicit, auditable step (not hidden inside the library).

---

## 3. Language & Framework: Python + FastAPI

### The Decision
All four services are written in Python 3.11 using FastAPI.

### Why FastAPI
- Auto-generated OpenAPI docs at `/docs` — useful during demo to show endpoints
- Type-checked request/response bodies with Pydantic — reduces bugs
- `async` support built-in — matters for the gateway which is just an HTTP proxy
- Lightweight — no framework magic to explain away in the live review

### Why Not Go / Node / Java
The spec says "business logic can stay simple." Using a language the candidate knows and can explain under pressure is more important than micro-optimising for the wrong thing. The bottleneck is the CPU-bound LLM, not the FastAPI services.

---

## 4. LLM Model: Qwen2.5-0.5B-Instruct

### The Decision
Use `Qwen/Qwen2.5-0.5B-Instruct` from HuggingFace.

### Why This Model
| Criterion | Why Qwen2.5-0.5B Passes |
|-----------|-------------------------|
| < 1B parameters | 0.5B — well under the limit |
| CPU-runnable | Yes, float32 weights, no CUDA dependency |
| Instruction-tuned | Yes — responds to Q&A prompts without fine-tuning |
| Loads fast enough for demo | ~30s on a modern MacBook CPU |
| License | Apache 2.0 — allows use in this assessment |
| Suggested by spec | Yes — spec explicitly suggests this model |

### Why We Use `torch_dtype=torch.float32`
On CPU, `bfloat16` requires AVX512 instruction support which not all laptops have. `float32` is universally supported and produces the same output quality for inference. The trade-off is more RAM (~2x) but the model is small enough that this is fine.

---

## 5. In-memory Catalog vs Database

### The Decision
The catalog stores items in a Python dict. No database.

### Why
The spec explicitly says: *"In-memory or static data is sufficient; a database is not required."*
Adding a database (Postgres, SQLite) would mean:
- Another Kubernetes deployment to manage
- Another PVC or init-volume
- More complexity to explain in the review

The in-memory approach is completely honest and adequate. We document it as a known limitation.

---

## 6. TLS: mkcert vs Self-signed OpenSSL vs cert-manager

### The Decision
Use `mkcert` to generate a locally-trusted TLS certificate.

### Why mkcert
| Option | Problem |
|--------|---------|
| `openssl req -x509 ...` | Browser shows "Not Secure" warning — you have to click through in the demo |
| cert-manager + Let's Encrypt | Requires real domain and internet access; overkill for local demo |
| mkcert | Installs a local CA into your OS trust store; browser shows the padlock ✅ |

The certificate is for `llm-app.local`, added to `/etc/hosts` → localhost. This is the cleanest demo experience.

### Certificate Is Not Committed to Git
`.gitignore` excludes `*.pem` and `*.key`. The mkcert cert is generated as part of the setup steps in the runbook. This is correct — TLS keys should never be in version control.

---

## 7. IP Allowlist: 127.0.0.1/32

### The Decision
The Nginx Ingress annotation restricts inbound access to `127.0.0.1/32` only.

### Why Only Localhost
The spec requires: *"restrict inbound access to specific IP ranges."*
Since this is a local Kind cluster, only your laptop can be a valid caller. Setting `127.0.0.1/32` is both correct and demonstrable: you can show the 403 response by simulating a request from a different IP (`curl --interface en0 ...` or `curl -H "X-Forwarded-For: 8.8.8.8"`).

### What This Would Be in Production
A specific corporate IP range or a set of office/VPN egress IPs. The mechanism (Nginx `whitelist-source-range` annotation) is identical.

---

## 8. Terraform: Separate tfvars vs Workspaces

### The Decision
Use **separate `.tfvars` files** (`dev.tfvars`, `prod.tfvars`) rather than Terraform workspaces.

### Why Not Workspaces
Workspaces are designed for state isolation but they share the same Terraform code and provider configuration. The problem: if dev and prod both try to create a Kind cluster named from the same variable, workspace switching can confuse the kind provider (which names clusters by a string, not workspace-aware). Additionally:
- Workspaces make it easy to accidentally `apply` to the wrong environment
- tfvars files are explicit, readable, and diffable

### How Separate State Works
```bash
# dev state lives in infra/terraform/terraform.tfstate.d/dev/ (if using workspaces)
# OR you use -state flag:
terraform apply -var-file=environments/dev.tfvars -state=dev.tfstate
terraform apply -var-file=environments/prod.tfvars -state=prod.tfstate
```

### How to Add a Third Environment (Staging)
1. Create `infra/terraform/environments/staging.tfvars`
2. Set values: `env_name = "staging"`, appropriate replicas, etc.
3. Run: `terraform apply -var-file=environments/staging.tfvars -state=staging.tfstate`
That's it — no code change needed.

---

## 9. Networking: ClusterIP for All Internal Services

### The Decision
Catalog, assistant, and LLM services use `type: ClusterIP`. Only the gateway is exposed via Ingress.

### Why
`ClusterIP` means the service is only reachable from within the cluster. There is no NodePort, no LoadBalancer. Combined with the NetworkPolicies, this creates two layers of isolation:
1. Network layer: ClusterIP — no external IP exists
2. Policy layer: NetworkPolicy — even within the cluster, only allowed pods can connect

### Gateway Uses ClusterIP Too
The gateway is also ClusterIP. The Nginx Ingress Controller is what makes it externally reachable — it proxies HTTPS traffic to the ClusterIP. This is the correct cloud-native pattern.

---

## 10. HPA: Gateway Only

### The Decision
HPA (HorizontalPodAutoscaler) is configured only for the gateway, not catalog, assistant, or LLM.

### Why Each Service Was Decided
| Service | Decision | Reason |
|---------|----------|--------|
| Gateway | HPA ✅ | Stateless HTTP proxy — trivially scales horizontally |
| Catalog | No HPA | Trivially fast in-memory reads; scaling gives no benefit |
| Assistant | No HPA | IO-bound (waits for LLM); scaling would queue more requests at LLM, not help |
| LLM | No HPA | CPU-bound + stateful (model in RAM); each replica costs ~2 GB RAM independently |

### How LLM Would Scale in Production
- GPU nodes with a model server like **vLLM** (request batching, async scheduling)
- Or **llama.cpp** server with quantized weights for much lower RAM per instance
- Or a model serving platform like **Triton Inference Server** with horizontal scaling based on queue depth

---

## 11. Security: Why `automountServiceAccountToken: false`

### The Decision
All ServiceAccounts have `automountServiceAccountToken: false`.

### Why
By default, Kubernetes mounts a bearer token into every pod that can be used to call the Kubernetes API. None of our services need to call the Kubernetes API — they only talk to each other over HTTP. Mounting the token is unnecessary attack surface: if a container is compromised, an attacker could use the token to enumerate cluster resources.

---

## 12. Observability: kube-prometheus-stack vs Custom Setup

### The Decision
Use the `kube-prometheus-stack` Helm chart (Prometheus + Grafana + Alertmanager bundled).

### Why
- One Helm install gives us everything: Prometheus, Grafana, node-exporter, kube-state-metrics, Alertmanager
- Pre-wired dashboards for Kubernetes cluster metrics out of the box
- The `PrometheusRule` CRD lets us add alert rules as Kubernetes resources (GitOps-friendly)

### Trade-off
The full stack uses ~500 MB RAM on a laptop. If resources are tight during the demo, disable it with `enable_observability=false` in tfvars and just show `kubectl logs` and `kubectl top pods`.

---

## 13. CronJob vs Separate Monitoring Service

### The Decision
Use a Kubernetes CronJob for daily model checksum verification and smoke prompts.

### Why CronJob
- Native Kubernetes primitive — no extra tooling needed
- Runs in the same namespace, has access to the model PVC and services
- Job logs are visible with `kubectl logs` and queryable in Grafana/Loki
- Failure is detectable via `kube_job_status_failed` Prometheus metric → alert rule

### Why Daily at 2 AM
Low-traffic time — doesn't compete with user requests for CPU. In production you'd adjust based on actual traffic patterns.

---

## 14. SBOM & Vulnerability Scanning

### The Decision
Use `syft` for SBOM generation and `trivy` for vulnerability scanning. Both are open-source and run locally.

### Why These Tools
| Tool | Alternative | Why We Chose |
|------|------------|--------------|
| syft | cyclonedx-gomod, cdxgen | syft works on Docker images without a running daemon; outputs SPDX JSON |
| trivy | grype, snyk | trivy is the most widely used, well-maintained, and can scan images + K8s + IaC |

### Vulnerability Threshold
We fail CI on `HIGH` or `CRITICAL` severity. `MEDIUM` and below are accepted for a demo. In production you'd tune this per-service and use `--ignore-unfixed` to suppress unfixable OS CVEs.

---

## 15. Assumptions Made

| # | Assumption | Based On |
|---|------------|----------|
| 1 | Docker Desktop is already installed and running | Required for Kind to work |
| 2 | Port 443 and 80 are free on the laptop | Kind needs to bind them for Ingress |
| 3 | Internet access is available for initial setup | Pulling base images, Helm charts, model weights |
| 4 | The laptop has ≥ 8 GB RAM | LLM pod uses ~2 GB, observability stack ~500 MB |
| 5 | macOS is the dev platform | All install commands use `brew` |
| 6 | HuggingFace Hub is reachable for model download | Required for first-time setup; air-gapped after that |
| 7 | `llm-app.local` resolves to 127.0.0.1 | `/etc/hosts` entry added manually as part of setup |
| 8 | mkcert CA is installed (`mkcert -install` was run) | Required for browser-trusted TLS |
| 9 | No real credentials are needed | Demo uses placeholder values in Secrets |
| 10 | The review happens on the same machine the cluster runs on | localhost-only Ingress allowlist |
