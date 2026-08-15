# ClickKart Platform

Spring Boot microservices platform. This repository is the **orchestration layer** — it holds the
docker-compose files, Kubernetes manifests, and platform-level documentation. Each service lives in
its own repository (table below) and is cloned as a sibling directory for local development.

---

## Architecture

Strict three-tier separation. Nothing skips a tier.

```
┌──────────────────────────────────────────────────────────────┐
│  Tier 1 — Presentation                                       │
│  Browser / client. Not yet built.                            │
└───────────────────────────┬──────────────────────────────────┘
                            │ HTTPS
┌───────────────────────────▼──────────────────────────────────┐
│  Tier 2 — Application                                        │
│                                                              │
│   API Gateway :8080  ← the ONLY internet-facing entry point   │
│        │  edge JWT validation, rate limiting, routing         │
│        ├──────────────┬──────────────┬─────────────────┐     │
│   Auth :8081   Notification :8082  Audit Log :8083  Captcha :8084
│                                                              │
│   Supporting: Eureka :8761 (discovery) · Config :8888        │
└───────────────────────────┬──────────────────────────────────┘
                            │ network only — never colocated
┌───────────────────────────▼──────────────────────────────────┐
│  Tier 3 — Data                                               │
│  PostgreSQL: one database + one least-privilege role per     │
│  service.  Redis: separate instances for gateway and captcha.│
└──────────────────────────────────────────────────────────────┘
```

**Why the tier boundary is enforced in the compose files:** `docker-compose.app-tier.yml` contains
zero datastores. Database and cache endpoints arrive as required, no-default environment variables,
so the application tier can never look like it "works" without a Tier-3 endpoint being supplied
deliberately. `docker-compose.dev-infra.yml` is the only place local stand-ins may exist.

---

## Repositories

| Repository | Port | Purpose |
|---|---|---|
| [clickkart-platform](https://github.com/kripals1199/clickkart-platform) | — | This repo: compose files, k8s manifests, platform docs |
| [clickkart-config-repository](https://github.com/kripals1199/clickkart-config-repository) | — | Runtime config, one branch per environment |
| [clickkart-eureka-server](https://github.com/kripals1199/clickkart-eureka-server) | 8761 | Service discovery |
| [clickkart-config-server](https://github.com/kripals1199/clickkart-config-server) | 8888 | Serves config from the config repo |
| [clickkart-api-gateway](https://github.com/kripals1199/clickkart-api-gateway) | 8080 | Edge routing, JWT validation, rate limiting |
| [clickkart-auth-service](https://github.com/kripals1199/clickkart-auth-service) | 8081 | Registration, login, JWT issuance, account management |
| [clickkart-notification-service](https://github.com/kripals1199/clickkart-notification-service) | 8082 | Password-reset / OTP dispatch (simulated) |
| [clickkart-audit-log-service](https://github.com/kripals1199/clickkart-audit-log-service) | 8083 | Tamper-evident hash-chained audit trail |
| [clickkart-captcha-service](https://github.com/kripals1199/clickkart-captcha-service) | 8084 | Self-hosted image CAPTCHA (no third-party provider) |
| [clickkart-user-service](https://github.com/kripals1199/clickkart-user-service) | 8085 | Customer profile and shipping address book |
| [clickkart-category-service](https://github.com/kripals1199/clickkart-category-service) | 8086 | Catalog taxonomy (public browsing, ADMIN management) |
| [clickkart-product-service](https://github.com/kripals1199/clickkart-product-service) | 8087 | Seller listings, variants, moderation workflow |
| [clickkart-inventory-service](https://github.com/kripals1199/clickkart-inventory-service) | 8088 | Per-SKU stock, reservation lifecycle, oversell guard |

---

## Configuration: one git branch per environment

`clickkart-config-repository` has exactly four environment branches — `dev`, `test`, `qa`, `prod` —
each holding only that environment's unsuffixed properties files. The **git branch is the
environment**; there is no filename suffix.

Every service's local `application.properties` sets:

```properties
spring.cloud.config.label=${SPRING_PROFILES_ACTIVE:dev}
```

Spring Cloud Config's `label` maps directly to a git branch, so a service started with
`SPRING_PROFILES_ACTIVE=qa` automatically pulls from the `qa` branch. Change the profile and the
service pulls from a different branch — no other wiring.

Eureka Server and Config Server are **not** config clients; they configure themselves from
properties baked into their images, to avoid a circular bootstrap dependency.

---

## Running locally

### Prerequisites

- Docker Desktop
- PostgreSQL running on the host (the compose files reach it via `host.docker.internal`)

### 1. Provision databases and roles

Three databases, each with its own least-privilege role. **Never use the `postgres` superuser** —
each role owns exactly one database and has `CONNECT` revoked on the others, so a leaked credential
cannot reach another service's data. Full SQL is in
[the config repo README](https://github.com/kripals1199/clickkart-config-repository#database-roles-each-environment-must-provision).

| Database | Role |
|---|---|
| `clickkart_auth` | `clickkart_auth_app` |
| `clickkart_notification` | `clickkart_notification_app` |
| `clickkart_audit_log` | `clickkart_audit_log_app` |
| `clickkart_user` | `clickkart_user_app` |
| `clickkart_category` | `clickkart_category_app` |
| `clickkart_product` | `clickkart_product_app` |
| `clickkart_inventory` | `clickkart_inventory_app` |

`clickkart_user` has a ready-to-run script — the password comes in as a psql variable so no
credential is ever committed:

```bash
psql -U postgres -h localhost -v user_db_password="$USER_DB_PASSWORD" -f scripts/provision-user-service-db.sql
```

### 2. Create your `.env`

```bash
cp .env.dev-infra.example .env
```

Then fill in the three generated database passwords. `.env` is gitignored and must never be
committed.

### 3. Start the stack

```bash
docker compose -f docker-compose.dev-infra.yml -f docker-compose.app-tier.yml up -d
```

Brings up 14 containers: 11 services, two Redis instances, and Mailpit as the local SMTP catcher.
Postgres is **not** containerized — it's your host install, so data survives `docker compose down`
without a Docker volume.

### 4. Verify

| What | Where |
|---|---|
| Aggregated Swagger UI | http://localhost:8080/swagger-ui.html |
| Eureka dashboard | http://localhost:8761 |
| Gateway health | http://localhost:8080/actuator/health |

---

## Security posture

- **Edge-only entry** — the Gateway is the sole internet-facing service; everything else is
  ClusterIP-only in Kubernetes.
- **JWT with server-side revocation** — logout invalidates an access token immediately via a
  Redis-backed revoked-`jti` store, which local signature validation alone cannot do.
- **Database isolation** — per-service least-privilege roles, `CONNECT` revoked cross-database.
- **CAPTCHA on abuse-prone public endpoints** — registration and password reset, fail-closed.
- **Rate limiting** — per-IP at both the Gateway and Auth Service, fail-closed on a Redis outage.
- **Tamper-evident audit trail** — every state change is hash-chained; the chain is verifiable.
- **No secrets in git** — every credential is an environment variable; non-dev profiles have no
  fallback and fail fast when one is missing.

---

## Project status

**Built and verified:** the eleven services above, running end-to-end locally with service
discovery, edge auth, database isolation, and full endpoint coverage.

**Not yet built:** Cart, Order, Payment and Admin. Sellers can list, operators can approve, and
stock can be held and released - but nothing assembles a basket or takes money yet.

**Known limitations:**
- Notification Service has real SMTP and MSG91 senders, but falls back to logging when no
  credentials are configured — so a dev environment silently does not deliver.
- Kubernetes manifests have not been applied to a live cluster.
- Category deletion cannot yet refuse a category that still has products, because Product Service
  does not exist to ask.
- `spring.jpa.hibernate.ddl-auto=update` is used in all environments; there is no migration tool.
- No TLS — all traffic is plain HTTP.
