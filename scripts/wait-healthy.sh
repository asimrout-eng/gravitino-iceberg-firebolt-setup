#!/usr/bin/env bash
# Polls critical containers until they are healthy or running
set -euo pipefail

SERVICES=(primary-postgres iceberg-postgres minio olake-ui gravitino)
TIMEOUT=240
INTERVAL=5

wait_for_service() {
  local svc="$1"
  local elapsed=0
  echo -n "  Waiting for $svc "
  while true; do
    STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$svc" 2>/dev/null || echo "missing")
    if [[ "$STATUS" == "healthy" ]]; then
      echo " ✓ healthy"
      return 0
    fi
    RUNNING=$(docker inspect --format='{{.State.Running}}' "$svc" 2>/dev/null || echo "false")
    if [[ "$STATUS" == "none" && "$RUNNING" == "true" ]]; then
      echo " ✓ running"
      return 0
    fi
    if [[ $elapsed -ge $TIMEOUT ]]; then
      echo " ✗ TIMED OUT (status=$STATUS)"
      return 1
    fi
    echo -n "."
    sleep $INTERVAL
    elapsed=$((elapsed + INTERVAL))
  done
}

for svc in "${SERVICES[@]}"; do
  wait_for_service "$svc"
done

echo ""
echo "All critical services are ready."
