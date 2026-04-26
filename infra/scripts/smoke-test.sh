#!/usr/bin/env bash
set -euo pipefail

LB_URL="${LB_URL:-http://localhost:8080}"

echo "=== Smoke Test ==="

echo "[1/3] Testing GET /health..."
HEALTH=$(curl -sf "$LB_URL/health")
echo "  Response: $HEALTH"

echo "[2/3] Testing POST /transaction..."
RESPONSE=$(curl -sf -X POST "$LB_URL/transaction" \
  -H "Content-Type: application/json" \
  -d '{
    "amount": 150.75,
    "card_type": "credit",
    "card_number_hash": "a1b2c3d4e5f6",
    "status": "approved"
  }')
echo "  Response: $RESPONSE"

echo "[3/3] Testing load distribution (10 requests)..."
for i in $(seq 1 10); do
  INSTANCE=$(curl -sf "$LB_URL/health" | python3 -c "import sys,json; print(json.load(sys.stdin)['instance'])")
  echo "  Request $i -> $INSTANCE"
done

echo "=== Smoke Test Complete ==="
