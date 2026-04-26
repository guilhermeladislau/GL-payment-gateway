#!/usr/bin/env bash
set -euo pipefail

LB_URL="${LB_URL:-http://localhost:8080}"
PG_PRIMARY_PORT="${PG_PRIMARY_PORT:-5432}"
PG_REPLICA_PORT="${PG_REPLICA_PORT:-5433}"

echo "=== RPO Validation ==="

echo "[1/5] Inserting test transaction via API..."
RESPONSE=$(curl -sf -X POST "$LB_URL/transaction" \
  -H "Content-Type: application/json" \
  -d '{
    "amount": 999.99,
    "card_type": "debit",
    "card_number_hash": "rpo_test_marker",
    "status": "approved"
  }')
echo "  Response: $RESPONSE"

TXN_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
echo "  Transaction ID: $TXN_ID"

echo "[2/5] Waiting 2 seconds for replication..."
sleep 2

echo "[3/5] Querying replica for transaction $TXN_ID..."
REPLICA_RESULT=$(docker exec pg-replica psql -U postgres -d gateway -t -A \
  -c "SELECT id FROM transactions WHERE id = '$TXN_ID';")

if [ "$REPLICA_RESULT" = "$TXN_ID" ]; then
  echo "  FOUND on replica. RPO = 0 (no data loss)."
else
  echo "  NOT FOUND on replica. Data loss detected."
fi

echo "[4/5] Stopping primary database..."
docker stop pg-primary

echo "[5/5] Verifying transaction on replica after primary failure..."
REPLICA_AFTER=$(docker exec pg-replica psql -U postgres -d gateway -t -A \
  -c "SELECT id FROM transactions WHERE id = '$TXN_ID';")

if [ "$REPLICA_AFTER" = "$TXN_ID" ]; then
  echo "  Transaction SURVIVES on replica after primary failure."
  echo "  RPO validated: data replicated before failure."
else
  echo "  Transaction LOST. RPO > 0."
fi

echo ""
echo "Restarting primary..."
docker start pg-primary
sleep 5
echo "Primary restarted."

echo "=== RPO Validation Complete ==="
