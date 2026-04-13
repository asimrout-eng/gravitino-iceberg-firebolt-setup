# Gravitino Iceberg REST Catalog + Firebolt Core Setup Guide

Set up Apache Gravitino as an Iceberg REST catalog with OAuth2 authentication, JDBC catalog backend (PostgreSQL), and S3-compatible storage (MinIO). Query Iceberg tables from Firebolt Core.

This guide includes a fully working local Docker demo with PostgreSQL CDC via OLake.

---

## Architecture

```
PostgreSQL (Source)          PostgreSQL (JDBC Catalog)
    port 5431                     port 5433
        |                    +----------------+
        |  WAL CDC           |  iceberg db    |
        v                    +-------+--------+
  +-----------+                      | reads metadata
  |   OLake   |                      |
  |   (CDC)   |                      v
  +-----+-----+            +--------------------+
        |                  |  Apache Gravitino   |
        |  writes Parquet  |  REST: port 9002    |---- OAuth2 ---- Auth Server
        v                  |  Mgmt:  port 8090   |                  port 8177
  +-----------+            +---------+----------+
  |   MinIO   |                      |
  |  port     |<---------------------+
  |  19000    |  vends s3 credentials
  +-----------+
        ^
        |  reads Parquet via s3://
  +-----+-----+
  |  Firebolt |
  |  Core     |
  |  port 3473|
  +-----------+
```

| Service | Role | Host Port |
|---|---|---|
| primary-postgres | Source DB with WAL logical replication | 5431 |
| iceberg-postgres | JDBC catalog metastore (Iceberg metadata) | 5433 |
| minio | S3-compatible object storage (Parquet/Iceberg files) | 19000 / 19001 |
| sample-auth-server | OAuth2 token server (JWT issuer for Gravitino) | 8177 |
| gravitino | Apache Gravitino Iceberg REST catalog | 8090 / 9002 |
| olake-ui | OLake web UI for CDC pipeline | 8000 |

---

## Prerequisites

- Docker and Docker Compose
- ~4 GB free memory for all containers
- Ports 5431, 5433, 8000, 8090, 8177, 9002, 19000, 19001 free

---

## Quick Start

### Step 1 -- Start All Services

```bash
git clone <this-repo-url>
cd gravitino-iceberg-firebolt-setup
make up
```

Wait ~90 seconds for all containers to become healthy. The `make up` command will report when all services are ready.

### Step 2 -- Configure OLake CDC Pipeline

Open http://localhost:8000 (login: `admin` / `password`).

#### Source (PostgreSQL CDC)

| Field | Value |
|---|---|
| Host | host.docker.internal |
| Port | 5431 |
| Database | demo |
| Username | olake |
| Password | password |
| Update Method | CDC |
| Replication Slot | olake_slot |
| Publication | olake_pub |

#### Destination (Iceberg + JDBC Catalog + MinIO)

| Field | Value |
|---|---|
| Catalog Type | jdbc |
| JDBC URL | jdbc:postgresql://host.docker.internal:5433/iceberg?sslmode=disable |
| Catalog Name | olake_iceberg |
| JDBC Username / Password | iceberg / password |
| Warehouse Path | s3a://warehouse |
| S3 Endpoint | http://host.docker.internal:19000 |
| Path Style | true |
| AWS Access Key / Secret | admin / password |

Create a job, select all 3 tables (customers, orders, products), and run Sync Now.

---

## Gravitino Configuration

### How Gravitino Connects to the JDBC Catalog

Gravitino runs as an Iceberg REST server that proxies the same JDBC catalog (PostgreSQL) that OLake writes to. The key configuration is in `gravitino/gravitino.conf`:

```properties
# JDBC catalog backend -- points to the same PostgreSQL that OLake uses
gravitino.iceberg-rest.catalog-backend = jdbc
gravitino.iceberg-rest.uri = jdbc:postgresql://iceberg-postgres:5432/iceberg
gravitino.iceberg-rest.jdbc-user = iceberg
gravitino.iceberg-rest.jdbc-password = password
gravitino.iceberg-rest.jdbc-driver = org.postgresql.Driver
gravitino.iceberg-rest.jdbc-initialize = true
gravitino.iceberg-rest.warehouse = s3a://warehouse
gravitino.iceberg-rest.catalog-backend-name = olake_iceberg
```

### S3 / MinIO Storage Configuration

```properties
gravitino.iceberg-rest.io-impl = org.apache.iceberg.aws.s3.S3FileIO
gravitino.iceberg-rest.s3-endpoint = http://minio:9000
gravitino.iceberg-rest.s3-region = us-east-1
gravitino.iceberg-rest.s3-path-style-access = true
gravitino.iceberg-rest.s3-access-key-id = admin
gravitino.iceberg-rest.s3-secret-access-key = password
```

For production with AWS S3, remove `s3-endpoint` and `s3-path-style-access`, and use IAM credentials or IRSA instead of static keys.

### Credential Vending

Gravitino vends S3 credentials to query engines so they can read Parquet files directly from storage:

```properties
gravitino.iceberg-rest.credential-providers = s3-secret-key
```

Available credential providers in Gravitino 1.2.0:

| Provider | Config Value | Use Case |
|---|---|---|
| S3 Secret Key | s3-secret-key | Passthrough static keys (MinIO, dev environments) |
| S3 Token | s3-token | STS AssumeRole with static keys |
| AWS IRSA | aws-irsa | EKS pods with IAM Roles for Service Accounts |

For production on EKS with IRSA, use `aws-irsa` instead of `s3-secret-key`.

### Custom Gravitino Docker Image

The `gravitino/Dockerfile` extends the official Gravitino image with two additional JARs:

1. PostgreSQL JDBC driver (for the JDBC catalog backend)
2. Gravitino Iceberg AWS bundle (for S3FileIO and credential vending)

Configuration files are `COPY`'d into the image rather than bind-mounted, because Gravitino's startup script rewrites config files in-place (which fails with Docker bind mounts).

---

## OAuth2 Authentication

### Overview

Gravitino is configured for OAuth2 authentication using JWKS-based token validation. Query engines (like Firebolt Core) obtain a JWT token from the OAuth2 server and present it to Gravitino.

### Configuration in gravitino.conf

```properties
gravitino.authenticators = simple,oauth
gravitino.authenticator.oauth.serviceAudience = test
gravitino.authenticator.oauth.tokenValidatorClass = org.apache.gravitino.server.authentication.JwksTokenValidator
gravitino.authenticator.oauth.jwksUri = http://sample-auth-server:8177/oauth2/jwks
gravitino.authenticator.oauth.allowSkewSecs = 60
```

Key settings:

| Property | Purpose |
|---|---|
| `gravitino.authenticators` | Enable both `simple` (anonymous) and `oauth` authentication |
| `tokenValidatorClass` | Use JWKS for dynamic public key fetching (no shared secrets) |
| `jwksUri` | URL where Gravitino fetches public keys to validate JWT signatures |
| `serviceAudience` | Expected `aud` claim in the JWT token |
| `allowSkewSecs` | Clock skew tolerance for token expiry validation |

### Demo OAuth2 Server

This setup includes a pre-configured OAuth2 server (`datastrato/sample-authorization-server:0.3.0`) from the Apache Gravitino project.

| Parameter | Value |
|---|---|
| Token endpoint | http://localhost:8177/oauth2/token |
| JWKS endpoint | http://localhost:8177/oauth2/jwks |
| Client ID | test |
| Client Secret | test |
| Scope | test |

For production, replace with your own OAuth2 provider (Keycloak, Okta, Azure AD, etc.) and update `jwksUri` and `serviceAudience` accordingly.

### Verifying the OAuth2 Flow

```bash
# 1. Get a JWT token
TOKEN=$(curl -s -X POST \
  'http://localhost:8177/oauth2/token' \
  -d 'grant_type=client_credentials&client_id=test&client_secret=test&scope=test' \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['access_token'])")

echo "Token: ${TOKEN:0:30}..."

# 2. Use it to authenticate to Gravitino REST API
curl -s http://localhost:9002/iceberg/v1/config \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool

# 3. Load a table with vended credentials (authenticated)
curl -s http://localhost:9002/iceberg/v1/namespaces/postgrestoicebergcdc_demo_public/tables/customers \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Iceberg-Access-Delegation: vended-credentials" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d.get('config',{}), indent=2))"
```

Expected vended credentials response:

```json
{
  "s3.access-key-id": "admin",
  "s3.secret-access-key": "password",
  "s3.endpoint": "http://minio:9000",
  "s3.path-style-access": "true"
}
```

---

## Verifying the Gravitino REST API

```bash
# List namespaces
curl -s http://localhost:9002/iceberg/v1/namespaces | python3 -m json.tool

# List tables
curl -s http://localhost:9002/iceberg/v1/namespaces/postgrestoicebergcdc_demo_public/tables | python3 -m json.tool

# Get table metadata
curl -s http://localhost:9002/iceberg/v1/namespaces/postgrestoicebergcdc_demo_public/tables/customers \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('Location:', d.get('metadata-location'))"
```

Or use the helper command:

```bash
make verify-gravitino
```

---

## Querying from Firebolt Core

### Starting Firebolt Core

```bash
docker run --detach --name firebolt-core --hostname firebolt-core \
    --security-opt seccomp=unconfined \
    --ulimit memlock=8589934592:8589934592 \
    --publish 127.0.0.1:3473:3473 \
    --network olake-demo-network \
    --mount type=bind,src=$(pwd)/firebolt-core-config.json,dst=/firebolt-core/config.json,readonly \
    ghcr.io/firebolt-db/firebolt-core:preview-rc
```

Wait ~15 seconds for the engine to start.

### Configuring firebolt-core-config.json

For S3-compatible storage (MinIO), set the custom endpoint:

```json
{
    "nodes": [{ "host": "localhost" }],
    "default_s3_endpoint_override": "http://minio:9000"
}
```

### Creating a Location (REST Catalog)

```sql
CREATE LOCATION gravitino_catalog
WITH
  SOURCE = ICEBERG
  CATALOG = REST
  CATALOG_OPTIONS = (
    URL       = 'http://gravitino:9001/iceberg'
    WAREHOUSE = ''
  )
  CREDENTIALS = (
    OAUTH_CLIENT_ID     = 'test'
    OAUTH_CLIENT_SECRET = 'test'
    OAUTH_SCOPE         = 'test'
    OAUTH_SERVER_URL    = 'http://sample-auth-server:8177/oauth2/token'
  );
```

Then query:

```sql
SELECT * FROM READ_ICEBERG(
    LOCATION => 'gravitino_catalog',
    NAMESPACE => 'postgrestoicebergcdc_demo_public',
    TABLE => 'customers'
) LIMIT 10;
```

### Alternative: Inline READ_ICEBERG

```sql
SELECT * FROM READ_ICEBERG(
    URL => 'http://gravitino:9001/iceberg',
    NAMESPACE => 'postgrestoicebergcdc_demo_public',
    TABLE => 'customers',
    OAUTH_CLIENT_ID => 'test',
    OAUTH_CLIENT_SECRET => 'test',
    OAUTH_SCOPE => 'test',
    OAUTH_SERVER_URL => 'http://sample-auth-server:8177/oauth2/token'
) LIMIT 10;
```

---

## Adapting for Production

### Replacing MinIO with AWS S3

1. In `gravitino/gravitino.conf`, remove `s3-endpoint` and `s3-path-style-access`
2. Set `s3-access-key-id` and `s3-secret-access-key` to real IAM credentials, or use `aws-irsa` credential provider on EKS
3. Update `warehouse` to your S3 bucket path (e.g., `s3a://my-bucket/iceberg`)
4. In `firebolt-core-config.json`, remove `default_s3_endpoint_override`

### Replacing the Demo OAuth2 Server

1. Deploy your preferred OAuth2 provider (Keycloak, Okta, Azure AD)
2. Create a client with `client_credentials` grant type
3. In `gravitino/gravitino.conf`, update:
   - `gravitino.authenticator.oauth.jwksUri` to your provider's JWKS endpoint
   - `gravitino.authenticator.oauth.serviceAudience` to your expected audience
4. In Firebolt SQL, update the `OAUTH_*` parameters to match your provider

### Using a Different JDBC Catalog Database

The JDBC catalog can use any PostgreSQL (or MySQL) database. Update these in `gravitino/gravitino.conf`:

```properties
gravitino.iceberg-rest.uri = jdbc:postgresql://<your-host>:<port>/<database>
gravitino.iceberg-rest.jdbc-user = <username>
gravitino.iceberg-rest.jdbc-password = <password>
```

Ensure this is the same database your data pipeline (OLake, Spark, etc.) writes Iceberg metadata to.

---

## Makefile Commands

```
make up                Start all services (OLake + Gravitino + Auth Server)
make status            Check all container status
make cdc-test          Insert CDC test rows into source Postgres
make verify            Verify Iceberg files in MinIO + JDBC catalog
make verify-gravitino  Verify Gravitino REST API + credential vending
make psql-src          Open psql on source Postgres
make psql-cat          Open psql on JDBC catalog Postgres
make logs              Tail all container logs
make down              Stop all containers
make clean             Stop + remove all volumes
```

---

## File Structure

```
.
├── docker-compose.yml              # All services (OLake CDC + Gravitino + Auth)
├── firebolt-core-config.json       # Firebolt Core config
├── Makefile                        # Helper commands
├── gravitino/
│   ├── Dockerfile                  # Custom image: base + JDBC driver + AWS bundle
│   ├── gravitino.conf              # Server config (OAuth + Iceberg REST + S3)
│   └── gravitino-iceberg-rest-server.conf
├── scripts/
│   ├── wait-healthy.sh
│   ├── cdc-test.sh
│   ├── verify-minio.sh
│   └── verify-gravitino.sh
└── README.md
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Source test: "role olake does not exist" | Wrong port in OLake source config | Use port 5431 (not 5432) |
| Gravitino 401 with Bearer token | OAuth misconfigured or token expired | Verify JWKS endpoint is reachable: `curl http://localhost:8177/oauth2/jwks` |
| Gravitino 404: "NoSuchCatalogException" | WAREHOUSE param not empty | Set `WAREHOUSE = ''` (empty) in `CREATE LOCATION` |
| Gravitino container keeps restarting | Config bind-mount issue | Configs must be COPY'd in Dockerfile, not bind-mounted (already handled) |
| "Device or resource busy" in Gravitino logs | Docker bind-mount conflict with startup script | Use the provided Dockerfile (bakes configs into the image) |

---

## References

- [OLake Documentation](https://olake.io/docs/getting-started/quickstart/)
- [Apache Gravitino 1.2.0 Docs](https://gravitino.apache.org/docs/1.2.0/)
- [Gravitino Iceberg REST Service](https://gravitino.apache.org/docs/1.2.0/iceberg-rest-service/)
- [Gravitino Authentication](https://gravitino.apache.org/docs/1.2.0/security/how-to-authenticate/)
- [Gravitino Credential Vending](https://gravitino.apache.org/docs/1.2.0/security/credential-vending/)
- [Firebolt Core Operations](https://docs.firebolt.io/firebolt-core/firebolt-core-operation)
- [Firebolt READ_ICEBERG](https://docs.firebolt.io/reference-sql/functions-reference/iceberg/read_iceberg)
- [Firebolt CREATE LOCATION](https://docs.firebolt.io/reference-sql/commands/data-definition/create-location-iceberg)
- [Apache Iceberg REST Catalog Spec](https://github.com/apache/iceberg/blob/main/open-api/rest-catalog-open-api.yaml)
