#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Split-Brain Validation Script
# ============================================================================
# Simulates a network partition between primary and replica to validate
# that the synchronous replication prevents data inconsistency.
#
# Scenario (TCC Section 3.3 - Cenario 3):
#   1. Insert a transaction on primary (confirmed by sync replication)
#   2. Disconnect replica from primary (network partition)
#   3. Attempt a new write on primary (should block/timeout due to sync commit)
#   4. Verify replica has consistent data up to partition point
#   5. Reconnect and verify cluster recovers
# ============================================================================

LB_URL="${LB_URL:-http://localhost:8080}"

echo "=== Split-Brain / Network Partition Validation ==="
echo ""

echo "[1/7] Verifying both database nodes are healthy..."
docker exec pg-primary pg_isready -U postgres > /dev/null
docker exec pg-replica pg_isready -U postgres > /dev/null

REPL_STATE=$(docker exec pg-primary psql -U postgres -t -A -c \
  "SELECT sync_state FROM pg_stat_replication WHERE application_name = 'pg-replica';")
echo "  Primary: OK"
echo "  Replica: OK (sync_state: $REPL_STATE)"

if [ "$REPL_STATE" != "sync" ]; then
  echo "  WARNING: Replication is NOT synchronous (state: $REPL_STATE)"
  echo "  Expected 'sync' for split-brain protection"
fi
echo ""

echo "[2/7] Inserting pre-partition transaction..."
PRE_RESPONSE=$(curl -sf -X POST "$LB_URL/transaction" \
  -H "Content-Type: application/json" \
  -d '{
    "amount": 100.00,
    "card_type": "credit",
    "card_number_hash": "pre_partition_test",
    "status": "approved"
  }')
PRE_TXN_ID=$(echo "$PRE_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
echo "  Pre-partition transaction: $PRE_TXN_ID"
sleep 1
echo ""

echo "[3/7] Verifying pre-partition transaction exists on replica..."
PRE_ON_REPLICA=$(docker exec pg-replica psql -U postgres -d gateway -t -A \
  -c "SELECT id FROM transactions WHERE id = '$PRE_TXN_ID';")

if [ "$PRE_ON_REPLICA" = "$PRE_TXN_ID" ]; then
  echo "  Transaction confirmed on replica (sync replication working)"
else
  echo "  ERROR: Transaction not found on replica"
  exit 1
fi
echo ""

echo "[4/7] Simulating network partition (disconnecting replica from primary)..."
docker network disconnect az-1 pg-replica 2>/dev/null || true
docker network disconnect az-2 pg-replica 2>/dev/null || true

# Reconnect replica to az-2 only (isolated from primary)
docker network connect az-2 pg-replica 2>/dev/null || true
echo "  Replica isolated from primary network"
sleep 2
echo ""

echo "[5/7] Attempting write during partition (should timeout with sync replication)..."
echo "  Sending POST /transaction with 5s timeout..."
PARTITION_START=$(python3 -c "import time; print(int(time.time() * 1000))")

HTTP_CODE=$(curl -sf -o /tmp/partition_response.txt -w "%{http_code}" \
  --max-time 5 \
  -X POST "$LB_URL/transaction" \
  -H "Content-Type: application/json" \
  -d '{
    "amount": 200.00,
    "card_type": "debit",
    "card_number_hash": "during_partition_test",
    "status": "approved"
  }' 2>/dev/null || echo "000")

PARTITION_END=$(python3 -c "import time; print(int(time.time() * 1000))")
PARTITION_DURATION=$((PARTITION_END - PARTITION_START))

if [ "$HTTP_CODE" = "000" ] || [ "$HTTP_CODE" = "504" ] || [ "$HTTP_CODE" = "500" ]; then
  echo "  EXPECTED BEHAVIOR: Write blocked/timed out (HTTP $HTTP_CODE, ${PARTITION_DURATION}ms)"
  echo "  Synchronous replication prevents writes without replica confirmation"
  WRITE_BLOCKED=true
else
  echo "  Write succeeded (HTTP $HTTP_CODE, ${PARTITION_DURATION}ms)"
  echo "  WARNING: This indicates async replication - data could be lost on failover"
  WRITE_BLOCKED=false
fi
echo ""

echo "[6/7] Restoring network connectivity..."
docker network disconnect az-2 pg-replica 2>/dev/null || true
docker network connect az-1 pg-replica 2>/dev/null || true
docker network connect az-2 pg-replica 2>/dev/null || true
echo "  Network restored. Waiting for replication to resume..."
sleep 5

REPL_STATE_AFTER=$(docker exec pg-primary psql -U postgres -t -A -c \
  "SELECT sync_state FROM pg_stat_replication WHERE application_name = 'pg-replica';" 2>/dev/null || echo "disconnected")
echo "  Replication state after recovery: $REPL_STATE_AFTER"
echo ""

echo "[7/7] Verifying data consistency after partition recovery..."
PRIMARY_COUNT=$(docker exec pg-primary psql -U postgres -d gateway -t -A \
  -c "SELECT COUNT(*) FROM transactions;")
sleep 2
REPLICA_COUNT=$(docker exec pg-replica psql -U postgres -d gateway -t -A \
  -c "SELECT COUNT(*) FROM transactions;")

echo "  Transactions on primary: $PRIMARY_COUNT"
echo "  Transactions on replica: $REPLICA_COUNT"

if [ "$PRIMARY_COUNT" = "$REPLICA_COUNT" ]; then
  echo "  Data is CONSISTENT after partition recovery"
else
  echo "  WARNING: Data INCONSISTENT - primary($PRIMARY_COUNT) vs replica($REPLICA_COUNT)"
fi

echo ""
echo "=== Split-Brain Validation Complete ==="
echo ""
echo "Results for TCC:"
echo "  Pre-partition replication: $REPL_STATE"
if [ "$WRITE_BLOCKED" = true ]; then
  echo "  Write during partition:    BLOCKED (sync replication enforced)"
  echo "  Data integrity:            PRESERVED (no split-brain possible)"
else
  echo "  Write during partition:    ALLOWED (async behavior detected)"
  echo "  Data integrity:            AT RISK (split-brain possible)"
fi
echo "  Post-partition recovery:   $REPL_STATE_AFTER"
echo "  Data consistency:          primary=$PRIMARY_COUNT replica=$REPLICA_COUNT"
