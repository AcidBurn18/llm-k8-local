# Quick guide: run the local application

This is the short path from a fresh checkout to a live request. For full explanations and recovery steps, use the [runbook](runbook.md). To make a code change and follow it into Kubernetes, use the [hands-on guide](hands-on-code-and-deployment.md).

## 1. Check the machine

Start Docker Desktop, then check the tools and resources in the [root README](../README.md#prerequisites). The local deployment needs internet access for package/chart/image downloads and the initial model download. Add `127.0.0.1 llm-app.local` to `/etc/hosts` if it is not already there.

## 2. Run the release

From the repository root:

```bash
make release ENV=dev
```

This runs lint, unit tests, image builds, SBOM generation, Trivy scans, Terraform plan/apply, Kind image loading, and Kubernetes deployment. When prompted by the Makefile, type `apply` to continue; then review and confirm Terraform's own plan with `yes`.

The normal Trivy gate fails on HIGH or CRITICAL findings. If you intentionally choose to proceed with the current findings for the local demo, use:

```bash
make release ENV=dev ALLOW_HIGH_VULNS=true
```

Review the reports under `docs/sbom-and-scans/`. The override allows the release; it does not fix findings.

## 3. Set up local HTTPS

The Ingress uses a Kubernetes TLS Secret that the release does not create. After the first release creates the `app` namespace:

```bash
mkdir -p infra/tls
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

Do not commit the generated private key. The smoke tests use `curl -k`, so they check the HTTPS route but skip trust verification.

## 4. Send a request and inspect the cluster

```bash
make verify ENV=dev
curl -k -X POST https://llm-app.local/api/v1/ask \
  -H 'Content-Type: application/json' \
  -d '{"question":"Summarize this item","item_id":"item-1"}'

kubectl get pods -n app --context kind-dev
kubectl logs -n app deployment/gateway --all-containers=true --context kind-dev
kubectl logs -n app deployment/llm -c llm --context kind-dev
kubectl top nodes --context kind-dev
kubectl top pods -n app --context kind-dev
```

To simulate an allowed and disallowed source IP from the Mac, use:

```bash
curl -k -i -H 'X-Forwarded-For: 127.0.0.1' https://llm-app.local/healthz
curl -k -i -H 'X-Forwarded-For: 203.0.113.10' https://llm-app.local/healthz
```

The first request should be allowed and the second blocked. The forwarded header is accepted only from the configured local proxy address. It is a local simulation, not a production client identity mechanism.

## 5. Stop or remove the environment

To roll back the gateway by one Kubernetes revision:

```bash
make rollback ENV=dev
```

To destroy the local Kind environment and its Terraform-managed resources:

```bash
make destroy ENV=dev
```

Destroy removes the selected cluster and is not a normal way to stop the application. After recreating the cluster, recreate the local TLS Secret and run `make verify ENV=dev` again. `dev` and `prod` use distinct Terraform roots and state directories; the `prod` example has not been deployed or tested.
