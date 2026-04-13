#!/usr/bin/env bash
# Verify Iceberg data in MinIO and JDBC catalog
set -euo pipefail

echo ""
echo "========================================================"
echo " VERIFY: Iceberg files in MinIO warehouse"
echo "========================================================"

echo ""
echo "--- MinIO bucket contents (warehouse) ---"
docker exec mc /usr/bin/mc ls --recursive minio/warehouse 2>/dev/null \
  | head -60 \
  || echo "  (No files yet — run a sync first in OLake UI)"

echo ""
echo "--- Parquet data files ---"
docker exec mc /usr/bin/mc find minio/warehouse --name "*.parquet" 2>/dev/null \
  | head -30 \
  || echo "  (No parquet files found yet)"

echo ""
echo "--- Iceberg metadata files ---"
docker exec mc /usr/bin/mc find minio/warehouse --name "*.avro" 2>/dev/null | head -10
docker exec mc /usr/bin/mc find minio/warehouse --name "*.json" 2>/dev/null | head -10

echo ""
echo "========================================================"
echo " VERIFY: JDBC Catalog tables in iceberg-postgres"
echo "========================================================"

echo ""
echo "--- iceberg_tables (registered Iceberg tables) ---"
docker exec -e PGPASSWORD=password iceberg-postgres \
  psql -U iceberg -d iceberg -c "\dt iceberg_*" 2>/dev/null \
  || echo "  (No iceberg catalog tables yet — run a sync first)"

echo ""
echo "--- Registered tables ---"
docker exec -e PGPASSWORD=password iceberg-postgres \
  psql -U iceberg -d iceberg \
  -c "SELECT catalog_name, table_namespace, table_name, metadata_location FROM iceberg_tables;" 2>/dev/null \
  || echo "  (iceberg_tables not created yet)"

echo ""
echo "========================================================"
echo " SOURCE: Row counts in PostgreSQL source tables"
echo "========================================================"

for TABLE in customers orders products; do
  COUNT=$(docker exec -e PGPASSWORD=password primary-postgres \
    psql -U olake -d demo -tAc "SELECT COUNT(*) FROM $TABLE;" 2>/dev/null || echo "?")
  echo "  $TABLE: $COUNT rows"
done

echo ""
echo "========================================================"
echo " DONE"
echo " MinIO Console → http://localhost:19001 (admin/password)"
echo "========================================================"
echo ""
