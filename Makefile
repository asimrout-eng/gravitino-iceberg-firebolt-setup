# ============================================================================
# OLake CDC + Gravitino (Iceberg REST) Demo
# PostgreSQL → OLake → Iceberg (JDBC + MinIO) → Gravitino REST → Firebolt
# ============================================================================

.PHONY: up down logs status cdc-test verify verify-gravitino psql-src psql-cat clean help

help:
	@echo ""
	@echo "  OLake + Gravitino Demo — Commands"
	@echo "  =================================="
	@echo ""
	@echo "  make up                Start all services (OLake + Gravitino)"
	@echo "  make status            Check all container status"
	@echo "  make logs-loader       Show data-loader logs (seeded data)"
	@echo "  make cdc-test          Insert CDC test rows into source Postgres"
	@echo "  make verify            Verify Iceberg files in MinIO + JDBC catalog"
	@echo "  make verify-gravitino  Verify Gravitino REST API + credential vending"
	@echo "  make psql-src          Open psql on source Postgres"
	@echo "  make psql-cat          Open psql on JDBC catalog Postgres"
	@echo "  make logs              Tail all container logs"
	@echo "  make logs-gravitino    Tail Gravitino logs"
	@echo "  make down              Stop all containers"
	@echo "  make clean             Stop + remove all volumes"
	@echo ""
	@echo "  URLs:"
	@echo "    OLake UI        → http://localhost:8000  (admin / password)"
	@echo "    MinIO Console   → http://localhost:19001 (admin / password)"
	@echo "    Gravitino UI    → http://localhost:8090"
	@echo "    Iceberg REST    → http://localhost:9002/iceberg/v1/"
	@echo ""

up:
	@echo "========================================================"
	@echo " Starting all services (OLake + Gravitino)..."
	@echo "========================================================"
	mkdir -p olake-data
	docker compose up -d --build --remove-orphans
	@echo ""
	@echo "Waiting for critical services to become healthy..."
	@bash scripts/wait-healthy.sh
	@echo ""
	@echo "All services are up!"
	@echo "  OLake UI        → http://localhost:8000  (admin / password)"
	@echo "  MinIO Console   → http://localhost:19001 (admin / password)"
	@echo "  Gravitino UI    → http://localhost:8090"
	@echo "  Iceberg REST    → http://localhost:9002/iceberg/v1/"

status:
	docker compose ps

logs-loader:
	docker logs data-loader 2>&1 || echo "(data-loader may have exited — expected)"

cdc-test:
	@bash scripts/cdc-test.sh

verify:
	@bash scripts/verify-minio.sh

verify-gravitino:
	@bash scripts/verify-gravitino.sh

psql-src:
	docker exec -it primary-postgres psql -U olake -d demo

psql-cat:
	docker exec -it iceberg-postgres psql -U iceberg -d iceberg

logs:
	docker compose logs -f --tail=50

logs-gravitino:
	docker logs gravitino -f --tail=100

logs-olake:
	docker logs demo-olake-ui -f --tail=50

logs-worker:
	docker logs demo-olake-temporal-worker -f --tail=50

down:
	docker compose down --remove-orphans

clean:
	docker compose down --remove-orphans -v
	rm -rf olake-data
