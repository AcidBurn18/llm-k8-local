# How to Run — Complete Step-by-Step Guide

> This is the most detailed guide for running the application from zero to a live demo.
> Every command is explained. Read through it once before you run anything.

---

## Table of Contents

1. [What You Need Before Starting](#1-what-you-need-before-starting)
2. [One-Time Setup](#2-one-time-setup)
3. [Understanding What Each Part Does](#3-understanding-what-each-part-does)
4. [Running the Application (Full Flow)](#4-running-the-application-full-flow)
5. [Verifying Everything Works](#5-verifying-everything-works)
6. [Running the LLM End-to-End](#6-running-the-llm-end-to-end)
7. [Demo: Security Features](#7-demo-security-features)
8. [Demo: Scaling](#8-demo-scaling)
9. [Demo: CronJob](#9-demo-cronjob)
10. [Demo: Rollback a Bad Release](#10-demo-rollback-a-bad-release)
11. [Demo: Observability](#11-demo-observability)
12. [Tearing Everything Down](#12-tearing-everything-down)
13. [Troubleshooting Common Issues](#13-troubleshooting-common-issues)

---

## 1. What You Need Before Starting

### Tools (install once)

Open a terminal and run these in order:

```bash
# Package manager
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Kubernetes cluster in Docker
brew install kind
# ^ Kind creates a real Kubernetes cluster where each "node" is actually a Docker container.
#   This means you get a real K8s API, real pods, real networking — all on your laptop.

# Kubernetes CLI
brew install kubectl
# ^ The command-line tool to talk to any Kubernetes cluster.

# Kubernetes package manager
brew install helm
# ^ Helm installs pre-packaged Kubernetes applications (charts). We use it for
#   Nginx Ingress Controller and the Prometheus monitoring stack.

# Infrastructure as Code
brew tap hashicorp/tap && brew install hashicorp/tap/terraform
# ^ Terraform creates and manages infrastructure declaratively. We use it to
#   create the Kind cluster and install Helm charts in the right order.

# Vulnerability scanner
brew install aquasecurity/trivy/trivy
# ^ Scans Docker images for known CVEs (Common Vulnerabilities and Exposures).
#   Our CI pipeline fails if any HIGH or CRITICAL CVEs are found.

# SBOM generator
brew install syft
# ^ Generates a Software Bill of Materials — a list of all packages inside
#   a Docker image. Required deliverable for the assessment.

# Local TLS certificate generator
brew install mkcert
mkcert -install
# ^ mkcert creates a local Certificate Authority (CA) on your machine and
#   installs it into your OS/browser trust store so self-signed certs
#   are trusted. You only run 'mkcert -install' once.

# JSON tool
brew install jq

# Python 3.11
brew install python@3.11
```

### Hardware Requirements

| Resource | Minimum | Why |
|----------|---------|-----|
| CPU cores | 4 | LLM inference uses all available cores |
| RAM | 8 GB | LLM pod ~2 GB + observability ~500 MB + K8s overhead |
| Free disk | 20 GB | Docker images ~3 GB, model weights ~1 GB, Kind node ~2 GB |

### Verify Docker is running

```bash
docker info
# Must show: Server: Docker Engine ... NOT "Cannot connect to the Docker daemon"
# If Docker is not running: open Docker Desktop from Applications
```

---

## 2. One-Time Setup

These steps only need to be run the **very first time** on a fresh machine.

### Step 2a — Add local DNS entry

```bash
echo "127.0.0.1  llm-app.local" | sudo tee -a /etc/hosts
```

**What this does**: Tells your OS that the hostname `llm-app.local` points to your own machine (127.0.0.1 = localhost). This is needed because the Ingress is configured for the host `llm-app.local`. Without this, `curl https://llm-app.local` would fail with a DNS error.

Verify it worked:
```bash
ping -c 1 llm-app.local
# Should show: 64 bytes from localhost (127.0.0.1)
```

### Step 2b — Generate TLS Certificate

```bash
cd /Users/iansh/Desktop/assingment1
mkdir -p infra/tls
cd infra/tls
mkcert llm-app.local
```

**What this creates**:
- `llm-app.local.pem` — the public certificate
- `llm-app.local-key.pem` — the private key

**Why self-signed?** We can't get a Let's Encrypt cert for a `.local` domain. mkcert installs its own local CA so the browser treats this cert as fully trusted (green padlock).

### Step 2c — Create the TLS Kubernetes Secret

> Wait until after the cluster is created (Step 4 creates it). Come back here after Step 4b.

```bash
kubectl create secret tls tls-secret \
  --cert=infra/tls/llm-app.local.pem \
  --key=infra/tls/llm-app.local-key.pem \
  -n app
```

**What this does**: Stores the TLS cert and key as a Kubernetes Secret. The Ingress resource references `secretName: tls-secret` to serve HTTPS. The key never leaves the cluster and is never in Git.

### Step 2d — Initialize Terraform

```bash
cd /Users/iansh/Desktop/assingment1/infra/terraform
terraform init
```

**What this does**: Downloads the three Terraform providers (kind, helm, kubernetes) from the Terraform registry into `.terraform/`. This is like `npm install` or `pip install`. Only needed once (or when you change provider versions).

Expected output:
```
Terraform has been successfully initialized!
```

---

## 3. Understanding What Each Part Does

Before you start deploying, understand the moving parts:

```
Your Terminal
    │
    ├─── Docker Desktop ── runs Kind nodes as Docker containers
    │         │
    │    Kind Cluster (name: dev)
    │         │
    │    Kubernetes API Server
    │         │
    │    Namespaces:
    │         ├── ingress-nginx   (Nginx Ingress Controller)
    │         ├── monitoring      (Prometheus + Grafana + Loki)
    │         └── app             (our 4 services)
    │               ├── gateway     (port 8000, 2 pods)
    │               ├── catalog     (port 8000, 1 pod)
    │               ├── assistant   (port 8000, 1 pod)
    │               └── llm         (port 8000, 1 pod + PVC for model weights)
    │
    └─── Terraform ── tells Kubernetes/Helm what to create
```

**Request flow when you curl the API:**
```
curl https://llm-app.local/api/v1/ask
  → /etc/hosts resolves llm-app.local → 127.0.0.1
  → Kind exposed port 443 → Nginx Ingress Controller pod
  → Nginx terminates TLS, checks IP allowlist (127.0.0.1 ✅)
  → HTTP → gateway pod (ClusterIP service)
  → gateway calls assistant pod
  → assistant calls catalog pod (if item_id provided)
  → assistant calls llm pod
  → llm runs inference on Qwen2.5-0.5B
  → answer bubbles back up the chain
  → curl receives JSON response
```

---

## 4. Running the Application (Full Flow)

### Step 4a — Preview what Terraform will create (no changes yet)

```bash
cd /Users/iansh/Desktop/assingment1/infra/terraform
terraform plan -var-file=environments/dev.tfvars
```

**What this shows**: Every resource Terraform will create — the Kind cluster, namespaces, Nginx Ingress Helm release, Prometheus Helm release. Review it. Nothing is created until you run `apply`.

Look for lines like:
```
+ resource "kind_cluster" "main" {
+ resource "helm_release" "ingress-nginx" {
+ resource "kubernetes_namespace" "app" {
```

### Step 4b — One-command build and deploy

From the project root:
```bash
cd /Users/iansh/Desktop/assingment1
make release ENV=dev
```

**What this does (in order)**:
1. `lint` — runs `ruff` to check Python code style
2. `test` — runs `pytest` (stubs for now)
3. `build` — runs `docker build` for all 4 images
4. `sbom` — runs `syft` to generate SBOMs for all images
5. `scan` — runs `trivy` to scan all images; **fails if HIGH/CRITICAL CVE found**
6. `load` — runs `kind load docker-image` for all 4 images into the cluster
7. `deploy` — runs `terraform apply` then `kubectl apply -R`

This takes about **5–10 minutes** the first time (Docker pulling base layers).

### Step 4c — Create the TLS Secret (first time only)

```bash
kubectl create secret tls tls-secret \
  --cert=infra/tls/llm-app.local.pem \
  --key=infra/tls/llm-app.local-key.pem \
  -n app
```

### Step 4d — Create app Secrets

```bash
# Placeholder secret for the demo
kubectl create secret generic app-secrets \
  --from-literal=api-key=demo-key-placeholder \
  --from-literal=model-checksum="" \
  -n app
```

> After the model downloads (Step 4e), update `model-checksum` with the real SHA-256.

### Step 4e — Download model weights (first time only)

```bash
# Apply the one-time download Job
kubectl apply -f infra/k8s/model-download-job.yaml

# Watch it run (takes 5–15 minutes depending on internet speed)
kubectl logs -f job/model-downloader -n app
```

**What happens inside the Job**:
1. Kubernetes creates a pod with the `llm:v1` image
2. The pod mounts the `model-weights-pvc` PersistentVolume at `/model-weights`
3. `download_model.py` runs and downloads ~1 GB of weights from HuggingFace
4. The script verifies the download and prints the SHA-256 checksum
5. The pod exits with code 0 (success)

After it completes, get the checksum:
```bash
kubectl logs job/model-downloader -n app | grep "SHA-256\|Checksum"
# Copy the SHA-256 hash

# Update the Secret with the real checksum
kubectl create secret generic app-secrets \
  --from-literal=api-key=demo-key-placeholder \
  --from-literal=model-checksum=<PASTE_SHA256_HERE> \
  -n app \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Step 4f — Check all pods are running

```bash
kubectl get pods -n app
```

Expected output (after LLM model loads, ~90 seconds):
```
NAME                         READY   STATUS    RESTARTS   AGE
gateway-5d8f9b6-xxx         1/1     Running   0          3m
gateway-5d8f9b6-yyy         1/1     Running   0          3m
catalog-7c9d4f-xxx          1/1     Running   0          3m
assistant-6b8e3c-xxx        1/1     Running   0          3m
llm-9f4a2d-xxx              1/1     Running   0          5m
```

If LLM shows `0/1 Running` — it's still loading the model. Wait and check logs:
```bash
kubectl logs deployment/llm -n app
# Should show: [startup] Loading model from /model-weights ... [startup] Model ready.
```

---

## 5. Verifying Everything Works

### Quick smoke test

```bash
make verify ENV=dev
# Runs 5 checks: gateway health, list items, get item, ask LLM, 404 handling
```

### Manual verification

```bash
# 1. Gateway is alive
curl -k https://llm-app.local/healthz
# Expected: {"status":"ok"}

# 2. List all catalog items
curl -k https://llm-app.local/api/v1/items | jq .
# Expected: array of 4 items with id, name, description, price

# 3. Get one specific item
curl -k https://llm-app.local/api/v1/items/item-1 | jq .
# Expected: {"id":"item-1","name":"Laptop Pro",...}

# 4. Get non-existent item → 404
curl -k -o /dev/null -w "%{http_code}" https://llm-app.local/api/v1/items/fake
# Expected: 404
```

> `-k` tells curl to skip TLS verification. In a browser, mkcert makes this unnecessary.

---

## 6. Running the LLM End-to-End

This is the most important demo step — a request that goes all the way through to the model:

```bash
# Ask a question about item-1 (this hits gateway → assistant → catalog + LLM)
curl -k -X POST https://llm-app.local/api/v1/ask \
  -H "Content-Type: application/json" \
  -d '{"question": "Summarize this product in one sentence.", "item_id": "item-1"}' \
  | jq .
```

**What happens internally** (trace it in logs):
```bash
# In separate terminals, watch logs from each service:
kubectl logs -f deployment/gateway   -n app   # will show incoming POST
kubectl logs -f deployment/assistant -n app   # will show catalog + LLM calls
kubectl logs -f deployment/llm       -n app   # will show inference running
```

Expected response (LLM output will vary slightly):
```json
{
  "answer": "The Laptop Pro is a high-performance laptop with 32GB RAM and 1TB SSD, priced at $1299.99."
}
```

**Why it takes 10–30 seconds**: The LLM is running on CPU. It processes tokens one at a time. With `max_new_tokens=200`, you're generating up to 200 tokens. On CPU this is ~0.5–2 tokens/second. This is expected behavior — document it as a known limitation.

---

## 7. Demo: Security Features

### 7a — Show IP allowlist is enforced

```bash
# This works (localhost):
curl -k https://llm-app.local/healthz
# Expected: {"status":"ok"}

# Simulate request from a different IP using X-Forwarded-For header:
curl -k -H "X-Forwarded-For: 1.2.3.4" https://llm-app.local/healthz
# Expected: 403 Forbidden

# Better: bind to a different interface if you have one
curl -k --interface en0 https://llm-app.local/healthz 2>/dev/null || echo "403 - blocked"
```

### 7b — Show NetworkPolicies work

```bash
# Start a debug pod in the app namespace
kubectl run debug --image=curlimages/curl -n app --rm -it --restart=Never \
  --overrides='{"spec":{"serviceAccountName":"catalog-sa"}}' \
  -- /bin/sh

# Inside the pod, try to reach the LLM directly (should be blocked by NetworkPolicy)
curl http://llm:8000/healthz
# Expected: connection refused or timeout (NetworkPolicy blocks it)

# But catalog is reachable from here? No — default-deny blocks it too
curl http://catalog:8000/healthz
# Expected: also blocked

exit
```

### 7c — Show pod security (non-root, read-only FS)

```bash
kubectl exec deployment/catalog -n app -- id
# Expected: uid=1000 (appuser) gid=1000 — NOT root

kubectl exec deployment/catalog -n app -- touch /test.txt
# Expected: Read-only file system error — proving readOnlyRootFilesystem works
```

---

## 8. Demo: Scaling

### Show HPA is configured

```bash
kubectl get hpa -n app
# Shows: gateway-hpa, min=1, max=3, current CPU utilization

kubectl describe hpa gateway-hpa -n app
# Shows the scaling policy details
```

### Trigger a scale-up (optional, needs metrics-server)

```bash
# Install metrics-server if not already present
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system \
  --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

# Wait for metrics-server to be ready (~30s)
kubectl rollout status deployment/metrics-server -n kube-system

# Generate load (in a separate terminal)
# Install hey: brew install hey
hey -z 60s -c 10 -m GET https://llm-app.local/api/v1/items

# Watch HPA in another terminal
watch kubectl get hpa gateway-hpa -n app
# Should see replica count increase from 1 toward 3
```

---

## 9. Demo: CronJob

### Show the CronJob exists

```bash
kubectl get cronjob -n app
# Shows: model-health-check, schedule 0 2 * * *

kubectl describe cronjob model-health-check -n app
```

### Trigger the CronJob manually (don't wait until 2 AM)

```bash
# Create a Job from the CronJob template
kubectl create job --from=cronjob/model-health-check manual-check -n app

# Watch it run
kubectl logs -f job/manual-check -n app

# Check exit code
kubectl get job manual-check -n app
# COMPLETIONS should show 1/1
```

---

## 10. Demo: Rollback a Bad Release

This shows zero-downtime rolling updates and rollback:

```bash
# Step 1: Show current rollout history
kubectl rollout history deployment/gateway -n app

# Step 2: Deploy a "bad" version (wrong image tag to simulate failure)
kubectl set image deployment/gateway gateway=gateway:bad -n app

# Step 3: Watch the rollout — it will stall because gateway:bad doesn't exist
kubectl rollout status deployment/gateway -n app
# After a while you see: Waiting for deployment rollout to finish

# Step 4: The readiness probe keeps the old pods running (maxUnavailable=0)
# The service continues to work during this time!
curl -k https://llm-app.local/healthz
# Still returns {"status":"ok"} — old pods still serving traffic

# Step 5: Roll back
kubectl rollout undo deployment/gateway -n app

# Step 6: Verify rollback completed
kubectl rollout status deployment/gateway -n app
# Expected: deployment "gateway" successfully rolled out
```

---

## 11. Demo: Observability

### Access Grafana

```bash
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80 &
# Open http://localhost:3000
# Username: admin
# Password: admin123
```

**Show in Grafana**:
1. **Kubernetes / Compute Resources / Namespace (Pods)** — pod CPU/memory in `app` namespace
2. **Kubernetes / Networking** — traffic between services
3. **Alerting** — show the GatewayHighErrorRate and CronJobFailed alert rules loaded

### View centralized logs

```bash
# If Loki is installed:
# In Grafana → Explore → Data source: Loki
# Query: {namespace="app"}
# Shows logs from all pods in the app namespace

# Or directly with kubectl:
kubectl logs -l app=gateway -n app --prefix --tail=50
kubectl logs -l app=llm -n app --prefix --tail=20
```

### Show metrics

```bash
# Port-forward Prometheus
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090 &
# Open http://localhost:9090

# Example query to run live:
# rate(http_requests_total{namespace="app"}[5m])
```

---

## 12. Tearing Everything Down

```bash
# Clean destroy — removes cluster, all K8s resources, frees ports 80 and 443
make destroy ENV=dev

# Verify cluster is gone
kind get clusters
# Expected: empty or "No kind clusters found."

# Verify Docker containers cleaned up
docker ps | grep kindest
# Expected: no output
```

---

## 13. Troubleshooting Common Issues

### "Port 443 already in use"

```bash
# Find what's using port 443
lsof -i :443
# Kill it or stop the process, then retry
```

### "Pod stuck in ImagePullBackOff"

```bash
kubectl describe pod <pod-name> -n app
# Look for: "Failed to pull image"
# Fix: image wasn't loaded into Kind. Run:
kind load docker-image <image>:v1 --name dev
```

### "LLM pod stuck in Init:0/1"

```bash
kubectl logs <pod-name> -c model-downloader -n app
# Could be: no internet, HuggingFace rate limit, insufficient disk space
# Check disk: df -h
```

### "curl: (60) SSL certificate problem"

```bash
# Use -k flag to skip verification, OR ensure mkcert CA is installed:
mkcert -install
# Then restart your browser/curl
```

### "Terraform error: cluster already exists"

```bash
# The Kind cluster exists but Terraform doesn't know about it
# Option 1: Destroy the existing cluster first
kind delete cluster --name dev

# Option 2: Import into Terraform state
terraform import kind_cluster.main dev

terraform apply -var-file=environments/dev.tfvars
```

### "HPA shows <unknown> for CPU"

```bash
# Metrics server is not running or not ready
kubectl get deployment metrics-server -n kube-system
# If not present, install it:
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system \
  --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

### "403 Forbidden from Ingress (even from localhost)"

```bash
# Check your source IP as seen by Nginx
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller | tail -20
# If you see requests from 10.x.x.x (pod network IP), update whitelist:
# nginx.ingress.kubernetes.io/whitelist-source-range: "127.0.0.1/32,10.0.0.0/8"
```
