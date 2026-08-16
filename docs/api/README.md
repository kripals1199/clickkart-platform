# ClickKart API

Everything a client can reach, in one place.

- **`ClickKart.postman_collection.json`** — 110 requests across 12 services, ready to import
- **`openapi/*.json`** — each service's OpenAPI document, harvested from the running service
- **Aggregated Swagger UI** — <http://localhost:8080/swagger-ui.html> when the stack is up

Both artefacts are **generated from the live services**, not hand-written, so they cannot drift into
describing endpoints that no longer exist. Regenerate with the steps at the bottom.

---

## One entry point

Every request in the collection goes to the **API Gateway** (`{{gatewayUrl}}`, default
`http://localhost:8080`), because that is the platform's only internet-facing component.

Per-service ports exist and are listed in the root README, but they are for debugging. A client that
called them directly would bypass the Gateway's JWT pre-check and its Redis-backed rate limiting —
a path no real client takes, and not one worth documenting as if it were supported.

## Getting a token

Import the collection, then **run `00 - Start here (login)` first**. It writes `accessToken` and
`refreshToken` into your environment, and collection-level bearer auth applies the access token to
every other request automatically. Nothing else needs a token pasted in.

Set `email` and `password` in the environment first. There is no seeded password in this repository
and there should not be one.

| Variable | Default | Notes |
|---|---|---|
| `gatewayUrl` | `http://localhost:8080` | Point at any environment |
| `email` / `password` | — | Yours to supply |
| `accessToken` / `refreshToken` | — | Written by the login request |

## What is deliberately not in here

**The `/internal/**` surfaces.** Order reading a basket, Payment reporting an outcome, Inventory's
reservation lifecycle — these are service-to-service routes authenticated by a per-service shared
secret. They have **no Gateway route at all**, and `springdoc.paths-to-exclude=/internal/**` keeps
them out of every OpenAPI document.

That is not an oversight to be corrected later. Publishing them would document a surface no client
can reach and advertise the shape of the platform's most privileged operations — the Inventory key
alone can move a shop's entire stock.

The processor webhook (`/webhooks/v1/payments/gateway`) is likewise absent. It is public by
necessity, but it is authenticated by an HMAC signature over the raw request body that only the
payment processor can produce.

---

## Roles

Four roles, and the collection's folders line up with them:

| Role | Reaches |
|---|---|
| `CUSTOMER` | own profile, addresses, cart, orders, payments |
| `SELLER` | own listings, own stock, own order lines |
| `ADMIN` | moderation, refunds, cross-service dashboards, audit trails |
| `DELIVERY_AGENT` | defined and seeded; no routes bound to it yet |

Requesting another person's resource returns **404, not 403**, throughout. A 403 confirms the id is
real, which is enough to enumerate a shop's order volume by probing references.

## Response shape

Every endpoint returns the same envelope:

```json
{
  "timestamp": "2026-08-16T10:00:00Z",
  "status": 200,
  "success": true,
  "data": { },
  "message": null,
  "path": "/api/v1/orders",
  "correlationId": "..."
}
```

On failure `data` is null and `error` carries a stable machine-readable `code` — branch on that,
never on the human-readable `message`.

The `correlationId` is minted by Auth Service at login and carried in the token, so one id follows a
request across every service it touches and appears in all of their logs and audit trails.

## Idempotency

Two operations require an **`Idempotency-Key` header** and will return `400` without one:

- `POST /api/v1/orders`
- `POST /api/v1/payments`

Both are money paths where a retry is otherwise a second charge. A replayed key returns the original
result rather than doing the work again.

---

## Regenerating

With the stack running:

```bash
for p in 8081:auth 8082:notification 8083:audit-log 8084:captcha 8085:user 8086:category \
         8087:product 8088:inventory 8089:order 8090:payment 8091:cart 8092:admin; do
  curl -s "http://localhost:${p%%:*}/v3/api-docs" -o "docs/api/openapi/${p##*:}.json"
done
```

Convert and merge:

```bash
for f in docs/api/openapi/*.json; do
  npx --yes openapi-to-postmanv2@4 -s "$f" -o "docs/api/.postman-parts/$(basename "$f")" -p \
      -O folderStrategy=Tags,requestParametersResolution=Example
done
node scripts/build-postman-collection.js docs/api/.postman-parts docs/api/ClickKart.postman_collection.json
```

The merge step is what the converter cannot do on its own: retarget every request at the Gateway,
add collection-level bearer auth, and prepend the login request that captures the token.
