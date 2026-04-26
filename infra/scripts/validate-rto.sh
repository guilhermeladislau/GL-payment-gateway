#!/usr/bin/env bash
set -euo pipefail

LB_URL="${LB_URL:-http://localhost:8080}"
CONTAINER="app-1"

echo "=== Validacao RTO / MTTR ==="

echo "[1/5] Verificando que ambas instancias estao saudaveis..."
for i in $(seq 1 4); do
  curl -sf "$LB_URL/health" > /dev/null
done
echo "  Ambas instancias respondendo."

echo "[2/5] Parando container '$CONTAINER' (kill imediato para simular crash)..."
STOP_TIME=$(python3 -c "import time; print(int(time.time() * 1000))")
docker stop -t 0 "$CONTAINER"
STOP_DONE=$(python3 -c "import time; print(int(time.time() * 1000))")
echo "  Container parado. docker stop levou $((STOP_DONE - STOP_TIME))ms"

echo "[3/5] Enviando requests ao LB ate recuperacao..."
FAIL_COUNT=0
SUCCESS_STREAK=0
REQUIRED_STREAK=5

while [ $SUCCESS_STREAK -lt $REQUIRED_STREAK ]; do
  HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" "$LB_URL/health" 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" = "200" ]; then
    SUCCESS_STREAK=$((SUCCESS_STREAK + 1))
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    SUCCESS_STREAK=0
  fi
  sleep 0.2
done
RECOVERED_TIME=$(python3 -c "import time; print(int(time.time() * 1000))")

RTO_MS=$((RECOVERED_TIME - STOP_TIME))
echo "[4/5] Resultados:"
echo "  Requests falhadas durante recuperacao: $FAIL_COUNT"
echo "  RTO (tempo total de recuperacao):      ${RTO_MS}ms"

echo "[5/5] Reiniciando '$CONTAINER'..."
docker start "$CONTAINER"
echo "  Container reiniciado."

echo "=== Validacao RTO Completa ==="
echo ""
echo "Para o TCC: RTO = ${RTO_MS}ms (~$((RTO_MS / 1000))s)"
