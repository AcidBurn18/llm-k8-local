#!/usr/bin/env bash
# scripts/teardown.sh
# Completely destroy the Kind cluster and clean up local state.
# Usage: bash scripts/teardown.sh [env]
set -euo pipefail

ENV="${1:-dev}"

echo "⚠️  Tearing down environment: ${ENV}"
echo ""

cd infra/terraform

echo "→ Terraform destroy..."
terraform init -input=false -reconfigure
terraform destroy -var-file=environments/"${ENV}".tfvars -auto-approve || true

echo "→ Deleting Kind cluster: ${ENV}..."
kind delete cluster --name "${ENV}" || true

echo ""
echo "✅  Teardown complete."
