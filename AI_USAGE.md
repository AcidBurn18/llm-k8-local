# AI Usage

## Tools Used

- **Antigravity (Google DeepMind)** — used throughout the project for code scaffolding, Kubernetes manifest generation, Terraform config, and documentation structure.

## How AI Was Used

| Task | AI Role | What I Did |
|------|---------|------------|
| FastAPI service scaffolding | Generated initial `main.py` for all four services | Reviewed every line, ran locally, verified behaviour |
| Dockerfile structure | Suggested non-root user pattern, seccomp, readOnly FS | Verified against Docker best-practices docs |
| Kubernetes manifests | Generated Deployment, Service, HPA, PDB, NetworkPolicy YAMLs | Read each field, tested with `kubectl apply --dry-run` |
| Terraform IaC | Generated Kind + Helm provider configs | Ran `terraform plan` and verified resources created |
| Makefile CI/CD | Suggested `check` and `release` target structure | Modified severity thresholds, tested each target |
| Security hardening | Listed security contexts, RBAC patterns | Cross-checked against K8s security docs |
| Documentation | Helped structure README, runbook, cloud-portability note | Rewrote sections to reflect my actual understanding |

## Example Prompts

- "Write a FastAPI service that returns a hardcoded list of items with /healthz, /items, /items/{id}"
- "Give me a Kubernetes Deployment for this service with non-root user, readOnlyRootFilesystem, and resource limits"
- "Write a Terraform config that creates a Kind cluster with port 443 exposed"

## What I Accepted / Rejected / Changed

- **Accepted**: Overall structure of FastAPI apps, Dockerfile multi-stage pattern, NetworkPolicy default-deny pattern
- **Rejected**: Overly complex Helm chart structure (simplified to raw manifests for clarity)
- **Changed**: Resource limits (AI suggested too-high values for a laptop), replaced with measured values

## How I Validated Output

- Ran each service locally with `uvicorn` and tested endpoints manually
- Applied each K8s manifest with `kubectl apply --dry-run=client` before live apply
- Read Terraform plan output line by line before approving apply

## Risks Considered

| Risk | Mitigation |
|------|-----------|
| Hallucinated API fields | Verified against official K8s/Terraform docs |
| Outdated package versions | Checked PyPI and Docker Hub for latest stable versions |
| Security gaps in generated manifests | Cross-referenced against CIS Kubernetes Benchmark |
| License issues in suggested libraries | Verified all dependencies are MIT/Apache 2.0 |
