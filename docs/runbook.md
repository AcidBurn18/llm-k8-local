# Runbook

## Prerequisites

Install all tools listed in the [README](../README.md#prerequisites).

Add the local DNS entry:
```bash
echo "127.0.0.1  llm-app.local" | sudo tee -a /etc/hosts
```

Generate TLS certificate:
```bash
cd infra/tls
mkcert llm-app.local
# Creates: llm-app.local.pem and llm-app.local-key.pem
```

## Setup (First Time Only)

```bash
# 1. Initialize Terraform
cd infra/terraform && terraform init

# 2. Review what will be created (no changes applied)
terraform plan -var-file=environments/dev.tfvars
```

## Deployment

```bash
# One command: build → scan → load → deploy
make release ENV=dev
```

Or step by step:

```bash
# Build images
make build

# Scan images
make scan

# Create Kind cluster via Terraform
cd infra/terraform
terraform apply -var-file=environments/dev.tfvars

# Load images into cluster
make load ENV=dev

# Apply Kubernetes manifests
kubectl apply -f infra/k8s/ -R --context kind-dev

# Run model download job
kubectl apply -f infra/k8s/model-download-job.yaml
kubectl wait --for=condition=complete job/model-downloader -n app --timeout=600s
```

## Verification

```bash
# Run built-in smoke tests
make verify ENV=dev

# Or manually:
curl -k https://llm-app.local/healthz
curl -k https://llm-app.local/api/v1/items
curl -k -X POST https://llm-app.local/api/v1/ask \
  -H "Content-Type: application/json" \
  -d '{"question":"What is this product?","item_id":"item-1"}'
```

## Rollback

```bash
# Roll back gateway to previous deployment
bash scripts/rollback.sh gateway app dev

# Or manually:
kubectl rollout undo deployment/gateway -n app --context kind-dev
```

## Teardown

```bash
# Remove everything cleanly
make destroy ENV=dev

# Or manually:
bash scripts/teardown.sh dev
```

## Troubleshooting

### Pod stuck in Pending
```bash
kubectl describe pod <pod-name> -n app
# Common causes: resource limits too high for laptop, PVC not bound
```

### LLM pod not starting
```bash
kubectl logs deployment/llm -n app
# Model loading takes ~30s — wait before checking
# Ensure model-download job completed first:
kubectl get job model-downloader -n app
```

### TLS not working in browser
```bash
# Ensure mkcert CA is installed:
mkcert -install
# Ensure /etc/hosts has the entry:
cat /etc/hosts | grep llm-app.local
```

### Ingress returning 404
```bash
kubectl get ingress -n app
kubectl describe ingress gateway-ingress -n app
# Ensure ingress-nginx controller is running:
kubectl get pods -n ingress-nginx
```

### Terraform apply fails with "cluster already exists"
```bash
# Kind cluster may already be running; either destroy it first or import:
kind delete cluster --name dev
terraform apply -var-file=environments/dev.tfvars
```
