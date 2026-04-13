#!/usr/bin/env bash
# Insert CDC test rows into the source PostgreSQL database
set -euo pipefail

PG_CONTAINER="primary-postgres"
PSQL="docker exec -e PGPASSWORD=password $PG_CONTAINER psql -U olake -d demo"

echo ""
echo "========================================================"
echo " CDC TEST: Inserting change events into source Postgres"
echo "========================================================"
echo ""

echo ">> INSERT: new customer (Eve Adams)"
$PSQL -c "
  INSERT INTO customers (name, email, country)
  VALUES ('Eve Adams', 'eve@example.com', 'Australia')
  ON CONFLICT DO NOTHING
  RETURNING id, name, email, country;
"

echo ""
echo ">> INSERT: new order for Eve Adams"
$PSQL -c "
  INSERT INTO orders (customer_id, product, amount, status)
  SELECT id, 'Smart Watch', 199.99, 'pending'
  FROM customers WHERE email = 'eve@example.com'
  RETURNING id, customer_id, product, amount, status;
"

echo ""
echo ">> UPDATE: Mark order #1 as 'returned'"
$PSQL -c "
  UPDATE orders SET status = 'returned', ordered_at = NOW()
  WHERE id = 1
  RETURNING id, product, status;
"

echo ""
echo ">> UPDATE: Reduce Laptop Pro stock by 2"
$PSQL -c "
  UPDATE products SET stock = stock - 2
  WHERE name = 'Laptop Pro 15'
  RETURNING id, name, stock;
"

echo ""
echo ">> INSERT BATCH: 3 new bulk orders"
$PSQL -c "
  INSERT INTO orders (customer_id, product, amount, status) VALUES
    (3, 'Laptop Pro 15',    1299.99, 'processing'),
    (5, '4K Monitor',       399.99,  'pending'),
    (7, 'External SSD 1TB', 109.99,  'shipped')
  RETURNING id, customer_id, product, amount, status;
"

echo ""
echo ">> DELETE: Remove order #12"
$PSQL -c "
  DELETE FROM orders WHERE id = 12
  RETURNING id, product, status;
"

echo ""
echo "========================================================"
echo " CDC TEST DONE — 6 change events fired"
echo " Go to OLake UI → Jobs → Sync Now"
echo " Then run: make verify"
echo "========================================================"
echo ""
