#!/usr/bin/env bash
# scripts/rollback.sh
# Roll back a specific deployment to its previous revision.
# Usage: bash scripts/rollback.sh [deployment-name] [namespace] [cluster-name]
set -euo pipefail

DEPLOYMENT="${1:-gateway}"
NAMESPACE="${2:-app}"
CLUSTER="${3:-dev}"
CONTEXT="kind-${CLUSTER}"

echo "→ Rollback: deployment/${DEPLOYMENT} in namespace ${NAMESPACE} on cluster ${CLUSTER}"
echo ""

# Show current rollout history
echo "=== Rollout history ==="
kubectl rollout history deployment/"${DEPLOYMENT}" -n "${NAMESPACE}" --context "${CONTEXT}"
echo ""

# Perform rollback
echo "=== Rolling back ==="
kubectl rollout undo deployment/"${DEPLOYMENT}" -n "${NAMESPACE}" --context "${CONTEXT}"

# Wait for rollout to complete
echo "=== Waiting for rollback to complete ==="
kubectl rollout status deployment/"${DEPLOYMENT}" -n "${NAMESPACE}" --context "${CONTEXT}" --timeout=60s

echo ""
echo "✅  Rollback complete."
kubectl get pods -n "${NAMESPACE}" --context "${CONTEXT}" -l app="${DEPLOYMENT}"
