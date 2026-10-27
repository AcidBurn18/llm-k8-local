# Operations runbook

This runbook covers the local Kind deployment in this repository. `dev` is the previously exercised environment. The `prod` configuration is an isolated assignment example and has not been verified as production infrastructure.

## Prerequisites

- Docker Desktop running; minimum 4 CPU cores, 8 GB RAM, and 20 GB free disk.
- Kind v0.23+, kubectl v1.29+, Helm v3.15+, Terraform v1.9+.
- Python 3.11 and pip; jq; mkcert (for local trusted TLS); Syft and Trivy.
- Internet access for tool/dependency installation and first model download from Hugging Face.
- Run commands from the repository root. The Makefile installs Ruff/Pytest dependencies as needed.

The documented install commands for macOS are in `README.md`. The `dev` cluster is selected with `ENV=dev`; use `ENV=prod` only when deliberately working with the separate example configuration.

## Setup and deployment

1. Start Docker Desktop and confirm the required tools are available.
2. Configure local TLS and hostname if browser-trusted HTTPS is needed: install mkcert's local CA (`mkcert -install`) and create the `llm-app.local` hosts entry/certificate per your local setup. The release does not create the Kubernetes `tls-secret`; HTTPS smoke checks use `curl -k` and therefore do not validate browser trust.
3. Review scan reports and make a deployment decision. The default release blocks on HIGH/CRITICAL findings. To explicitly pass that gate while retaining reports, set `ALLOW_HIGH_VULNS=true` only after reviewing the findings.
4. Run:

   ```bash
   make release ENV=dev
   ```

   This lints and tests services, builds four `:v1` images, creates Syft SBOMs, scans images with Trivy, shows Terraform plan, asks for `apply` and Terraform's final confirmation, loads images into Kind, applies Kubernetes manifests, and waits for deployments. The LLM init container downloads/verifies the pinned model to the PVC if absent.

For a build and scan without deployment, use `make check`. For the `prod` example, use `make release ENV=prod`; its ingress URL is `https://llm-app.local:8443`.

## Verification

Run the included smoke checks:

```bash
make verify ENV=dev
```

The suite checks gateway health, catalog list/detail, an end-to-end ask reaching the LLM, 404 behavior, and ingress allowlist behavior. `make verify ENV=prod` targets the `:8443` URL.

Inspect rollout and model state:

```bash
kubectl get pods,svc,pvc -n app --context kind-dev
kubectl rollout status deployment/gateway -n app --context kind-dev
kubectl rollout status deployment/catalog -n app --context kind-dev
kubectl rollout status deployment/assistant -n app --context kind-dev
kubectl rollout status deployment/llm -n app --context kind-dev --timeout=300s
kubectl exec -n app deployment/llm --context kind-dev -- sha256sum /model-weights/data/model.safetensors
```

Expected model hash: `fdf756fa7fcbe7404d5c60e26bff1a0c8b8aa1f72ced49e7dd0210fe288fb7fe`. The smoke suite does not prove every infrastructure failure mode; see the root README's known limitations.

## Rollback

The Makefile rollback target reverts the gateway Deployment only:

```bash
make rollback ENV=dev
```

For another Deployment, use the helper script (arguments: deployment, namespace, cluster name):

```bash
bash scripts/rollback.sh llm app dev
```

Review rollout history first if selecting a specific revision. The helper performs `kubectl rollout undo` and waits for readiness. To recover from a bad image/config change, restore the intended manifests/image tag, rebuild and reload the image if needed, then redeploy. Rollback does not reverse Terraform infrastructure changes or restore model PVC contents.

## Teardown

Destroying removes the Kind cluster and its resources, including the model PVC data. Confirm the target environment before running:

```bash
make destroy ENV=dev
```

Terraform destroy is configured with `-auto-approve`. Alternatively, `bash scripts/teardown.sh dev` also deletes the Kind cluster; it uses `infra/terraform/environments/<env>.tfvars`, which is not present in the current repository, so prefer the Makefile target for this checkout. Use `ENV=prod` only when intentionally removing that separate example cluster.

## Troubleshooting

| Symptom | Checks and action |
|---|---|
| Terraform cannot reach the cluster | Confirm Docker is running and the selected Kind cluster exists: `kind get clusters`; inspect `kubectl config get-contexts`. Use context `kind-dev` for dev. |
| Terraform plan/apply or destroy fails | Confirm the environment root is `infra/terraform/environments/dev` (or `prod`), initialize Terraform there, and inspect the first provider/resource error. Destroy needs the cluster still accessible to Terraform. |
| Image pull failure | Images are local and use `imagePullPolicy: Never`; rebuild with `make build`, then load each image using `kind load docker-image <service>:v1 --name dev`. |
| Model downloader cannot reach Hugging Face | Check cluster egress/network policy and Hugging Face availability. Inspect `kubectl logs -n app deployment/llm --context kind-dev -c model-downloader` (init container) or `kubectl logs -n app job/model-downloader --context kind-dev`. |
| Model checksum mismatch | Compare the file's SHA-256 with the pinned expected value. Check revision, interrupted download, and PVC contents. Do not silently change the configured checksum. |
| LLM pod stays unready or ask request is slow | Inspect `kubectl describe pod -n app -l app=llm --context kind-dev` and `kubectl logs -n app deployment/llm --context kind-dev`; CPU inference and initial model load can take time and use substantial memory. |
| HTTPS/browser certificate warning | The release does not create `tls-secret`. Complete mkcert certificate setup for the hostname; `curl -k` bypasses trust validation and does not establish browser trust. |
| Trivy gate fails | Review `docs/sbom-and-scans/*-trivy.txt`, rebuild/patch affected dependencies or base images, regenerate reports with `make check`. HIGH/CRITICAL override is available only as a deliberate, reviewed exception. |
| HPA has no metrics | Wait for Metrics Server/APIService readiness; inspect `kubectl get apiservice v1beta1.metrics.k8s.io` and `kubectl top pods -n app --context kind-dev`. |

## SBOM and vulnerability scan evidence

Generated artifacts are in [`docs/sbom-and-scans/`](docs/sbom-and-scans/): SPDX JSON SBOMs and Trivy text reports for `gateway:v1`, `catalog:v1`, `assistant:v1`, and `llm:v1`. `make check` regenerates them using Syft and scans using Trivy. The Makefile gates HIGH and CRITICAL findings by default.

The recorded report metadata identifies Syft `1.55.0` in the SBOM creator field. Image versions are tagged `v1`; the LLM base image is `python:3.11-slim` pinned by digest in `services/llm/Dockerfile`. The checked-in LLM scan report lists 44 OS vulnerabilities for its Debian 13.7 layer and includes dependency findings, including a Critical PyTorch finding; read the full report before release. Scanner databases and vulnerability results change over time, so these checked-in reports describe the scan snapshot and should be regenerated for a current release. The Trivy version is not embedded in the checked-in text reports; record the installed `trivy --version` alongside each newly generated set.
