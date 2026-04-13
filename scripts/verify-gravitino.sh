#!/usr/bin/env bash
# Verify Gravitino Iceberg REST API is working and can see OLake tables
set -euo pipefail

echo ""
echo "========================================================"
echo " VERIFY: Gravitino Iceberg REST Catalog"
echo "========================================================"

echo ""
echo "--- 1. Gravitino server version ---"
curl -sf http://localhost:8090/api/version 2>/dev/null | python3 -m json.tool \
  || echo "  ✗ Gravitino management API not reachable on port 8090"

echo ""
echo "--- 2. Iceberg REST config endpoint ---"
curl -sf http://localhost:9002/iceberg/v1/config 2>/dev/null | python3 -m json.tool \
  || echo "  ✗ Iceberg REST API not reachable on port 9002"

echo ""
echo "--- 3. List namespaces ---"
NAMESPACES=$(curl -sf http://localhost:9002/iceberg/v1/namespaces 2>/dev/null)
if [ -n "$NAMESPACES" ]; then
  echo "$NAMESPACES" | python3 -m json.tool
else
  echo "  (No namespaces yet — run an OLake sync first)"
fi

echo ""
echo "--- 4. List tables per namespace ---"
if [ -n "$NAMESPACES" ]; then
  for NS in $(echo "$NAMESPACES" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for ns in data.get('namespaces', []):
    print('.'.join(ns))
" 2>/dev/null); do
    echo ""
    echo "  Namespace: $NS"
    curl -sf "http://localhost:9002/iceberg/v1/namespaces/${NS}/tables" 2>/dev/null \
      | python3 -m json.tool \
      || echo "  (error listing tables)"
  done
fi

echo ""
echo "--- 5. Test credential vending (X-Iceberg-Access-Delegation) ---"
if [ -n "$NAMESPACES" ]; then
  FIRST_NS=$(echo "$NAMESPACES" | python3 -c "
import sys, json
data = json.load(sys.stdin)
ns_list = data.get('namespaces', [])
if ns_list:
    print('.'.join(ns_list[0]))
" 2>/dev/null)

  if [ -n "$FIRST_NS" ]; then
    TABLES=$(curl -sf "http://localhost:9002/iceberg/v1/namespaces/${FIRST_NS}/tables" 2>/dev/null)
    FIRST_TABLE=$(echo "$TABLES" | python3 -c "
import sys, json
data = json.load(sys.stdin)
ids = data.get('identifiers', [])
if ids:
    print(ids[0].get('name', ''))
" 2>/dev/null)

    if [ -n "$FIRST_TABLE" ]; then
      echo ""
      echo "  Loading table ${FIRST_NS}.${FIRST_TABLE} with vended credentials..."
      RESPONSE=$(curl -sf \
        -H "X-Iceberg-Access-Delegation: vended-credentials" \
        "http://localhost:9002/iceberg/v1/namespaces/${FIRST_NS}/tables/${FIRST_TABLE}" 2>/dev/null)
      if [ -n "$RESPONSE" ]; then
        echo "$RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
config = data.get('config', {})
if any(k.startswith('s3') for k in config):
    print('  ✓ Credential vending is working! Received S3 config:')
    for k, v in sorted(config.items()):
        if k.startswith('s3') or k.startswith('client'):
            val = v[:20] + '...' if len(v) > 20 else v
            print(f'    {k} = {val}')
else:
    print('  ⚠ Table loaded but no S3 credentials in config. Config keys:')
    for k in sorted(config.keys()):
        print(f'    {k}')
" 2>/dev/null
      else
        echo "  ✗ Failed to load table"
      fi
    else
      echo "  (No tables found to test credential vending)"
    fi
  fi
else
  echo "  (No namespaces — skipping credential vending test)"
fi

echo ""
echo "========================================================"
echo " Gravitino Endpoints:"
echo "   Management UI  → http://localhost:8090"
echo "   Iceberg REST   → http://localhost:9002/iceberg/v1/"
echo "========================================================"
echo ""
