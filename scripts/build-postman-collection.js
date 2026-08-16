// scripts/build-postman-collection.js
//
// Merges the per-service Postman collections (converted from each service's live OpenAPI document)
// into one collection, and adds the parts a generated collection never has: collection-level bearer
// auth, variables, and a login request that captures the token so every other request just works.
//
// Regenerate with:  node scripts/build-postman-collection.js
// after refreshing docs/api/openapi/*.json from the running services.

const fs = require('fs');
const path = require('path');

const IN = process.argv[2] || '/tmp/pmout';
const OUT = process.argv[3] || 'docs/api/ClickKart.postman_collection.json';

// Everything reaches the platform through the Gateway, because that is the only internet-facing
// entry point. Per-service ports are listed in the README for direct debugging, but a collection
// that hit them directly would exercise a path no real client uses - and would silently skip the
// Gateway's JWT pre-check and rate limiting.
const GATEWAY = '{{gatewayUrl}}';

const SERVICE_ORDER = [
  'auth', 'user', 'category', 'product', 'inventory',
  'cart', 'order', 'payment', 'admin', 'captcha', 'notification', 'audit-log',
];

/** Rewrites a generated request's URL to go through the Gateway. */
function retarget(item) {
  if (item.item) { item.item.forEach(retarget); return; }
  const r = item.request;
  if (!r || !r.url) return;
  const u = r.url;
  const rawPath = Array.isArray(u.path) ? u.path.join('/') : (u.path || '');
  u.raw = `${GATEWAY}/${rawPath}`;
  u.host = [GATEWAY];
  delete u.port;
  delete u.protocol;
}

const folders = [];
for (const name of SERVICE_ORDER) {
  const file = path.join(IN, `${name}.json`);
  if (!fs.existsSync(file)) continue;
  const col = JSON.parse(fs.readFileSync(file, 'utf8'));
  const items = col.item || [];
  items.forEach(retarget);
  folders.push({
    name: `${name}-service`,
    description: (col.info && col.info.description) || '',
    item: items,
  });
}

// The one request that has to come first, and the reason this collection is usable at all: it logs
// in and stores the tokens, so nothing else needs a token pasted into it by hand.
const authFolder = {
  name: '00 - Start here (login)',
  description:
    'Run this first. It logs in and writes accessToken/refreshToken into the environment, which every '
    + 'other request picks up through collection-level bearer auth.\n\n'
    + 'The platform mints correlation ids at login and every service reads them from the token, so a '
    + 'request made after this one is traceable end to end.',
  item: [
    {
      name: 'Login (captures tokens)',
      event: [
        {
          listen: 'test',
          script: {
            type: 'text/javascript',
            exec: [
              'const body = pm.response.json();',
              'const data = body.data || {};',
              'if (data.accessToken) {',
              '    pm.environment.set("accessToken", data.accessToken);',
              '    pm.environment.set("refreshToken", data.refreshToken || "");',
              '    pm.test("logged in", () => pm.response.to.have.status(200));',
              '} else {',
              '    pm.test("login returned tokens", () => { throw new Error("no accessToken in response"); });',
              '}',
            ],
          },
        },
      ],
      request: {
        method: 'POST',
        header: [{ key: 'Content-Type', value: 'application/json' }],
        url: { raw: `${GATEWAY}/api/v1/auth/login`, host: [GATEWAY], path: ['api', 'v1', 'auth', 'login'] },
        body: {
          mode: 'raw',
          raw: JSON.stringify({ email: '{{email}}', password: '{{password}}' }, null, 2),
        },
        description: 'Public route - no token required. Everything after this one uses the token it stores.',
      },
    },
  ],
};

const collection = {
  info: {
    _postman_id: '9f3c1f60-0000-4000-8000-clickkart0001',
    name: 'ClickKart',
    description:
      'Generated from each service\'s live OpenAPI document, then merged and wired up.\n\n'
      + '**Every request goes through the API Gateway** (`{{gatewayUrl}}`, default `http://localhost:8080`), '
      + 'because that is the platform\'s only internet-facing entry point. Calling a service port directly '
      + 'would skip the Gateway\'s JWT pre-check and rate limiting - a path no real client takes.\n\n'
      + '**Run `00 - Start here` first.** It captures the tokens; collection-level bearer auth does the rest.\n\n'
      + '**What is deliberately absent:** the `/internal/**` surfaces. They are shared-secret routes between '
      + 'services, have no Gateway route at all, and are excluded from the OpenAPI documents by '
      + '`springdoc.paths-to-exclude`. A collection that included them would be documenting a surface no '
      + 'client can reach.\n\n'
      + 'Regenerate with `node scripts/build-postman-collection.js`.',
    schema: 'https://schema.getpostman.com/json/collection/v2.1.0/collection.json',
  },
  auth: {
    type: 'bearer',
    bearer: [{ key: 'token', value: '{{accessToken}}', type: 'string' }],
  },
  variable: [
    { key: 'gatewayUrl', value: 'http://localhost:8080', type: 'string' },
    { key: 'email', value: 'asha.menon@example.com', type: 'string' },
    { key: 'password', value: '', type: 'string' },
    { key: 'accessToken', value: '', type: 'string' },
    { key: 'refreshToken', value: '', type: 'string' },
  ],
  item: [authFolder, ...folders],
};

fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, JSON.stringify(collection, null, 2));

const count = (items) => items.reduce((n, i) => n + (i.item ? count(i.item) : 1), 0);
console.log(`  folders:  ${collection.item.length}`);
console.log(`  requests: ${count(collection.item)}`);
console.log(`  written:  ${OUT}`);
