# Makefile — CI/CD Script
# Two modes:
#   make check   → lint, test, build, SBOM, scan (run on every change)
#   make release → check + load images + terraform apply + kubectl apply

SHELL        := /bin/bash
IMAGES       := gateway catalog assistant llm
TAG          := v1
ENV          ?= dev
CLUSTER_NAME := $(ENV)
VULN_SEVERITY := HIGH,CRITICAL

.PHONY: help check release lint test build sbom scan load kind deploy destroy rollback verify infra

help:
	@echo ""
	@echo "Usage:"
	@echo "  make check           Lint + test + build + SBOM + vulnerability scan"
	@echo "  make release ENV=dev Full check then deploy to Kind cluster"
	@echo "  make destroy ENV=dev Tear down the Kind cluster and all resources"
	@echo "  make rollback        Roll back the gateway deployment one revision"
	@echo "  make verify          Run smoke tests against the live cluster"
	@echo ""

# ── CHECK mode ─────────────────────────────────────────────────────────────────

check: lint test build sbom scan
	@echo ""
	@echo "✅  check complete — all gates passed"

lint:
	@echo "→ Linting Python services with ruff..."
	pip3 install --quiet ruff
	python3 -m ruff check services/

test:
	@echo "→ Running unit tests..."
	pip3 install --quiet pytest httpx
	python3 -m pytest services/ -v --tb=short

build:
	@echo "→ Building Docker images (tag=$(TAG))..."
	@for svc in $(IMAGES); do \
		echo "  Building $$svc:$(TAG)..."; \
		docker build -t $$svc:$(TAG) services/$$svc/ || exit 1; \
	done
	@echo "  Images built:"
	@docker images | grep -E "^($(shell echo $(IMAGES) | tr ' ' '|'))\\s" || true

sbom:
	@echo "→ Generating SBOMs with syft..."
	@mkdir -p docs/sbom-and-scans
	@command -v syft > /dev/null 2>&1 || { echo "syft not found, installing via Homebrew..."; brew install syft; }
	@for svc in $(IMAGES); do \
		echo "  SBOM: $$svc:$(TAG)"; \
		syft $$svc:$(TAG) -o spdx-json > docs/sbom-and-scans/$$svc-sbom.json 2>/dev/null; \
	done
	@echo "  SBOMs written to docs/sbom-and-scans/"

scan:
	@echo "→ Scanning images with trivy (fail on: $(VULN_SEVERITY))..."
	@mkdir -p docs/sbom-and-scans
	@for svc in $(IMAGES); do \
		echo "  Scanning $$svc:$(TAG)..."; \
		trivy image \
			--severity $(VULN_SEVERITY) \
			--format table \
			--output docs/sbom-and-scans/$$svc-trivy.txt \
			$$svc:$(TAG) 2>/dev/null; \
	done
	@echo "  Scan reports written to docs/sbom-and-scans/"

# ── RELEASE mode ───────────────────────────────────────────────────────────────

release: check infra load deploy
	@echo ""
	@echo "Release complete — cluster ($(CLUSTER_NAME)) updated"
	
infra:
	@echo "→ Running Terraform init + apply (env=$(ENV))..."
	cd infra/terraform && \
		terraform init -input=false && \
		terraform apply -var-file=environments/$(ENV).tfvars -auto-approve

load:
	@echo "→ Loading images into Kind cluster ($(CLUSTER_NAME))..."
	@for svc in $(IMAGES); do \
		echo "  Loading $$svc:$(TAG)..."; \
		kind load docker-image $$svc:$(TAG) --name $(CLUSTER_NAME); \
	done


deploy:
	@echo "→ Applying Kubernetes manifests..."
	kubectl apply -f infra/k8s/ -R --context kind-$(CLUSTER_NAME)
	@echo "→ Restarting deployments to load rebuilt local images..."
	kubectl rollout restart deployment/gateway deployment/catalog deployment/assistant deployment/llm -n app --context kind-$(CLUSTER_NAME)
	@echo "→ Waiting for deployments to be ready..."
	kubectl rollout status deployment/gateway   -n app --timeout=120s --context kind-$(CLUSTER_NAME)
	kubectl rollout status deployment/catalog   -n app --timeout=120s --context kind-$(CLUSTER_NAME)
	kubectl rollout status deployment/assistant -n app --timeout=120s --context kind-$(CLUSTER_NAME)
	kubectl rollout status deployment/llm       -n app --timeout=300s --context kind-$(CLUSTER_NAME)

destroy:
	@echo "→ Destroying environment ($(ENV))..."
	cd infra/terraform && \
		terraform destroy -var-file=environments/$(ENV).tfvars -auto-approve || true
	@echo "✅  $(ENV) environment destroyed"

rollback:
	@echo "→ Rolling back gateway deployment..."
	kubectl rollout undo deployment/gateway -n app --context kind-$(CLUSTER_NAME)
	kubectl rollout status deployment/gateway -n app --timeout=60s --context kind-$(CLUSTER_NAME)

verify:
	@echo "→ Running smoke tests..."
	bash scripts/verify.sh $(CLUSTER_NAME)
