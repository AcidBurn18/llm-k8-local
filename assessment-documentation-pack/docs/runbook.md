# Runbook

This runbook describes the local `dev` environment. I tested it on macOS with Docker Desktop and Kind.

## Prerequisites

- Docker Desktop with at least 4 CPU cores, 8 GB RAM, and 20 GB free disk.
- Kind, kubectl, Helm, Terraform, Python 3.11, jq, Syft, Trivy, and mkcert. Minimum versions and install links are in the [README](../README.md#prerequisites).
- Ports 80 and 443 available on the Mac for Kind Ingress.
- Network access for base images, tools, Helm charts, Python packages, and the initial Hugging Face model download.

Check Docker Desktop is running and make sure `llm-app.local` resolves to localhost:

```bash
grep llm-app.local /etc/hosts || echo '127.0.0.1 llm-app.local' | sudo tee -a /etc/hosts
docker info
```

## Initialize and review infrastructure

The release target initializes Terraform, shows a plan, and asks for two approvals before it applies infrastructure. No separate manual Terraform apply is required.

```bash
make release ENV=dev
```

At the Makefile prompt, type `apply`; then review the Terraform plan and type `yes` at Terraform's confirmation prompt. Any other Makefile response cancels before apply. The release runs lint, unit tests, image builds, SBOM generation, vulnerability scans, Terraform, Kind image loading, and Kubernetes deployment. It waits for Metrics Server and application rollouts.

If you knowingly want the release to continue despite HIGH or CRITICAL image findings, pass the explicit override. Trivy still runs and saves its reports:

```bash
make release ENV=dev ALLOW_HIGH_VULNS=true
```

The override changes the Trivy exit-code gate; it does not hide the results. Read the [scan report notes](sbom-and-scans/README.md) and the per-image reports before sharing or promoting images.

## Local TLS certificate

The Ingress refers to a Kubernetes Secret named `tls-secret`, but the release does not create it. After the first release has created the `app` namespace, create a local mkcert certificate and apply it as a Secret:

```bash
cd infra/tls
mkcert -install
mkcert llm-app.local
kubectl create secret tls tls-secret \
  --cert=llm-app.local.pem \
  --key=llm-app.local-key.pem \
  -n app --context kind-dev \
  --dry-run=client -o yaml | kubectl apply -f - --context kind-dev
cd ../..
```

Keep the generated key out of Git. The smoke script uses `curl -k`: it verifies HTTPS routing but skips certificate trust validation. For a browser trust check, install the mkcert CA on the Mac and open `https://llm-app.local`.

## Verify the deployment

```bash
make verify ENV=dev
kubectl get pods -n app --context kind-dev
kubectl get job model-downloader -n app --context kind-dev
kubectl get hpa -n app --context kind-dev
kubectl top nodes --context kind-dev
kubectl top pods -n app --context kind-dev
```

The recorded dev release passed all six smoke checks, including an end-to-end request through the gateway to the LLM and allowlist checks for a localhost client address and a blocked TEST-NET address. Metrics Server returned node and application pod metrics. HPA scale-up under load, CronJob execution, NetworkPolicy enforcement, and alert firing were not demonstrated.

To inspect Grafana, use a local port-forward:

```bash
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80 --context kind-dev
```

Then open `http://localhost:3000`. The current Terraform chart values set the demo login to `admin` / `admin123`; this password is in the Terraform configuration and must be replaced with proper secret handling before any shared or production use.

## Logs and diagnosis

```bash
# See pod status, placement, and recent events
kubectl get pods -n app -o wide --context kind-dev
kubectl get events -n app --sort-by=.lastTimestamp --context kind-dev

# Follow a service's logs
kubectl logs -n app deployment/gateway --context kind-dev --all-containers=true -f
kubectl logs -n app deployment/assistant --context kind-dev --all-containers=true -f
kubectl logs -n app deployment/llm --context kind-dev -c llm -f

# Inspect the LLM init container or model downloader Job
kubectl logs -n app deployment/llm -c model-downloader --context kind-dev
kubectl logs -n app job/model-downloader --context kind-dev
kubectl describe job model-downloader -n app --context kind-dev

# Inspect Ingress and TLS Secret presence
kubectl describe ingress gateway-ingress -n app --context kind-dev
kubectl get secret tls-secret -n app --context kind-dev

# Inspect Metrics Server and APIService
kubectl get pods -n kube-system -l k8s-app=metrics-server --context kind-dev
kubectl get apiservice v1beta1.metrics.k8s.io --context kind-dev
```

Common symptoms:

| Symptom | Check |
|---|---|
| Terraform says cluster exists or provider cannot connect | Inspect `kind get clusters`, Terraform state, and `kubectl config get-contexts`. Do not delete the cluster manually while Terraform still owns it; use `make destroy ENV=dev` when you intend a full teardown. |
| TLS browser warning or Ingress default certificate | Recreate `tls-secret` using the mkcert instructions. `curl -k` does not test browser trust. |
| LLM pod stuck in `Init` or `CrashLoopBackOff` | Check both `model-downloader` Job logs and the LLM `model-downloader` init-container logs; then check PVC status, free Docker disk, and the configured checksum Secret. |
| `kubectl top` or HPA says metrics unavailable | Check Metrics Server rollout and `v1beta1.metrics.k8s.io` APIService. It uses `--kubelet-insecure-tls` for local Kind only. |
| App request times out | Check Ingress, gateway, assistant, and LLM logs in that order. CPU inference can take time on a laptop. |
| Ingress rejects the client | Use the `make verify` cases and inspect the `whitelist-source-range` annotation and trusted proxy setting. Avoid trusting an entire Docker subnet for forwarded client IPs. |

## Rollback

The provided Makefile rollback command rolls back only the gateway Deployment by one Kubernetes revision:

```bash
make rollback ENV=dev
```

For another app Deployment, use `kubectl rollout undo deployment/<name> -n app --context kind-dev` and wait for it with `kubectl rollout status`. A bad-release rollback was not demonstrated in the recorded assessment run. This local rollback also depends on the Deployment having a previous revision; it is not a full infrastructure rollback.

## Teardown and recreate

`make destroy` runs Terraform destroy with automatic yes approval; it deletes the local Kind cluster and its resources. Use it only when you intend to remove the environment:

```bash
make destroy ENV=dev
make release ENV=dev ALLOW_HIGH_VULNS=true
```

After recreating, recreate the `tls-secret` as described above, then run `make verify ENV=dev`. Terraform state is local to each environment root under `infra/terraform/environments/`.

## Scheduled model check

The `model-health-check` CronJob is scheduled daily at 02:00 UTC. It checks the model checksum and sends a test prompt to the assistant. The release applies this CronJob but does not trigger it or wait for its result. To run it manually, create a one-off Job from the CronJob and inspect its logs:

```bash
kubectl create job --from=cronjob/model-health-check model-health-check-manual -n app --context kind-dev
kubectl logs -n app job/model-health-check-manual --context kind-dev -f
```

Delete the manual Job after inspection if you want to keep the namespace tidy. Failed Jobs can also be viewed with `kubectl get jobs -n app` and the `CronJobFailed` Prometheus alert rule, though alert loading and delivery are not verified.
