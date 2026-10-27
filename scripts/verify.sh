#!/usr/bin/env bash
# scripts/verify.sh
# Run smoke tests against the live cluster.
# Usage: bash scripts/verify.sh [cluster-name] [base-url]
set -euo pipefail

CLUSTER="${1:-dev}"
HOST="llm-app.local"
BASE="${2:-https://${HOST}}"
ALLOWED_CLIENT_IP="127.0.0.1"
PASS=0
FAIL=0

ok()   { echo "  ✅  $*"; ((PASS += 1)); }
fail() { echo "  ❌  $*"; ((FAIL += 1)); }

echo ""
echo "=== Smoke Tests — cluster: ${CLUSTER} ==="
echo ""

# The Kind host port is local-only. NGINX trusts X-Forwarded-For only from the
# exact Docker bridge gateway, so this header simulates an allowlisted client.
curl_allowed() {
  curl --noproxy '*' -sk -H "X-Forwarded-For: ${ALLOWED_CLIENT_IP}" "$@"
}

# 1. Gateway healthz
echo "[1] Gateway health check..."
if curl_allowed "${BASE}/healthz" | grep -q '"ok"'; then
  ok "GET /healthz → 200 ok"
else
  fail "GET /healthz — unexpected response"
fi

# 2. List items
echo "[2] List catalog items..."
ITEMS=$(curl_allowed "${BASE}/api/v1/items")
if echo "$ITEMS" | grep -q '"item-1"'; then
  ok "GET /api/v1/items → contains item-1"
else
  fail "GET /api/v1/items — item-1 not found"
fi

# 3. Get single item
echo "[3] Get single item (item-2)..."
ITEM=$(curl_allowed "${BASE}/api/v1/items/item-2")
if echo "$ITEM" | grep -q '"Wireless Mouse"'; then
  ok "GET /api/v1/items/item-2 → Wireless Mouse"
else
  fail "GET /api/v1/items/item-2 — unexpected response"
fi

# 4. Ask question (reaches LLM)
echo "[4] Ask question via /api/v1/ask (LLM end-to-end)..."
ANSWER=$(curl_allowed -X POST "${BASE}/api/v1/ask" \
  -H "Content-Type: application/json" \
  -d '{"question":"Say hello in one word.","item_id":"item-1"}')
if echo "$ANSWER" | grep -q '"answer"'; then
  ok "POST /api/v1/ask → LLM returned an answer"
  echo "     LLM response: $(echo "$ANSWER" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('answer','')[:100])")"
else
  fail "POST /api/v1/ask — no 'answer' field in response"
fi

# 5. Item not found returns 404
echo "[5] Non-existent item returns 404..."
STATUS=$(curl_allowed -o /dev/null -w "%{http_code}" "${BASE}/api/v1/items/does-not-exist")
if [ "$STATUS" = "404" ]; then
  ok "GET /api/v1/items/does-not-exist → 404"
else
  fail "GET /api/v1/items/does-not-exist → expected 404, got ${STATUS}"
fi

# 6. Ingress allowlist accepts an allowed client and rejects an untrusted one.
echo "[6] Ingress IP allowlist..."
ALLOWED_STATUS=$(curl_allowed -o /dev/null -w "%{http_code}" "${BASE}/healthz")
BLOCKED_STATUS=$(curl --noproxy '*' -sk -H "X-Forwarded-For: 203.0.113.10" \
  -o /dev/null -w "%{http_code}" "${BASE}/healthz")
if [ "$ALLOWED_STATUS" = "200" ] && [ "$BLOCKED_STATUS" = "403" ]; then
  ok "Ingress allows ${ALLOWED_CLIENT_IP} and blocks 203.0.113.10"
else
  fail "Ingress allowlist expected 200/403, got ${ALLOWED_STATUS}/${BLOCKED_STATUS}"
fi

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
echo ""

[ "$FAIL" -eq 0 ] || exit 1
