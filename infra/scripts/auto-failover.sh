#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Auto-Failover Script for PostgreSQL Primary -> Replica Promotion
# ============================================================================
# This script monitors the primary database and automatically promotes
# the replica to primary when a failure is detected.
#
# In production, this role would be handled by Patroni + etcd/Consul.
# This PoC implementation demonstrates the failover concept.
# ============================================================================

PRIMARY_CONTAINER="${PRIMARY_CONTAINER:-pg-primary}"
REPLICA_CONTAINER="${REPLICA_CONTAINER:-pg-replica}"
CHECK_INTERVAL=3           # seconds between health checks
MAX_FAILURES=3             # consecutive failures before failover
FAILURE_COUNT=0

echo "=== PostgreSQL Auto-Failover Monitor ==="
echo "  Primary: $PRIMARY_CONTAINER"
echo "  Replica: $REPLICA_CONTAINER"
echo "  Check interval: ${CHECK_INTERVAL}s"
echo "  Failover after: $MAX_FAILURES consecutive failures"
echo ""

check_primary() {
  docker exec "$PRIMARY_CONTAINER" pg_isready -U postgres > /dev/null 2>&1
}

check_replica() {
  docker exec "$REPLICA_CONTAINER" pg_isready -U postgres > /dev/null 2>&1
}

promote_replica() {
  echo ""
  echo "[FAILOVER] Promoting replica to primary..."

  PROMOTE_START=$(python3 -c "import time; print(int(time.time() * 1000))")

  # Promote the replica
  docker exec "$REPLICA_CONTAINER" pg_ctl promote -D /var/lib/postgresql/data 2>/dev/null || \
    docker exec "$REPLICA_CONTAINER" psql -U postgres -c "SELECT pg_promote();" 2>/dev/null

  # Wait for replica to accept writes
  WRITE_READY=false
  for i in $(seq 1 30); do
    if docker exec "$REPLICA_CONTAINER" psql -U postgres -d gateway -c "SELECT 1;" > /dev/null 2>&1; then
      IS_RECOVERY=$(docker exec "$REPLICA_CONTAINER" psql -U postgres -t -A -c "SELECT pg_is_in_recovery();")
      if [ "$IS_RECOVERY" = "f" ]; then
        WRITE_READY=true
        break
      fi
    fi
    sleep 1
  done

  PROMOTE_END=$(python3 -c "import time; print(int(time.time() * 1000))")
  PROMOTE_TIME=$((PROMOTE_END - PROMOTE_START))

  if [ "$WRITE_READY" = true ]; then
    echo "[FAILOVER] Replica promoted successfully in ${PROMOTE_TIME}ms"
    echo "[FAILOVER] $REPLICA_CONTAINER is now accepting writes"
    echo ""
    echo "=== Failover Summary ==="
    echo "  Detection time: $((MAX_FAILURES * CHECK_INTERVAL))s (${MAX_FAILURES} checks x ${CHECK_INTERVAL}s)"
    echo "  Promotion time: ${PROMOTE_TIME}ms"
    echo "  Total RTO:      ~$((MAX_FAILURES * CHECK_INTERVAL * 1000 + PROMOTE_TIME))ms"
    return 0
  else
    echo "[FAILOVER] ERROR: Replica promotion failed or timed out"
    return 1
  fi
}

echo "[MONITOR] Starting health check loop..."

while true; do
  if check_primary; then
    if [ $FAILURE_COUNT -gt 0 ]; then
      echo "[MONITOR] Primary recovered after $FAILURE_COUNT failure(s)"
    fi
    FAILURE_COUNT=0
  else
    FAILURE_COUNT=$((FAILURE_COUNT + 1))
    echo "[MONITOR] Primary health check FAILED ($FAILURE_COUNT/$MAX_FAILURES)"

    if [ $FAILURE_COUNT -ge $MAX_FAILURES ]; then
      echo "[MONITOR] Primary unreachable after $MAX_FAILURES checks"

      if check_replica; then
        promote_replica
        exit $?
      else
        echo "[MONITOR] ERROR: Replica is also unreachable. Manual intervention required."
        exit 1
      fi
    fi
  fi

  sleep $CHECK_INTERVAL
done
