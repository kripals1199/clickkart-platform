#!/usr/bin/env bash
#
# Generates the local TLS material for the API Gateway.
#
# Development only. This mints a self-signed certificate, which browsers will warn about and no
# client should ever be told to trust blindly outside a laptop. Real environments get a
# certificate from a CA - the Gateway config is identical either way, only the keystore differs.
#
#   TLS_KEYSTORE_PASSWORD='...' ./scripts/generate-dev-tls.sh
#
# The password is taken from the environment and never written to disk or echoed. The keystore it
# produces is gitignored: these repositories are public, and a committed keystore is a published
# private key.

set -euo pipefail

CERT_DIR="${CERT_DIR:-certs}"
KEYSTORE="${CERT_DIR}/gateway-keystore.p12"
DAYS="${TLS_VALID_DAYS:-365}"

if [[ -z "${TLS_KEYSTORE_PASSWORD:-}" ]]; then
  echo "TLS_KEYSTORE_PASSWORD is not set." >&2
  echo "Generate one and keep it in .env, which is gitignored:" >&2
  echo "  openssl rand -base64 32" >&2
  exit 1
fi

if [[ ${#TLS_KEYSTORE_PASSWORD} -lt 12 ]]; then
  echo "TLS_KEYSTORE_PASSWORD is shorter than 12 characters. Use a generated value." >&2
  exit 1
fi

command -v openssl >/dev/null || { echo "openssl not found on PATH." >&2; exit 1; }

mkdir -p "${CERT_DIR}"

if [[ -f "${KEYSTORE}" && "${1:-}" != "--force" ]]; then
  echo "${KEYSTORE} already exists. Re-run with --force to replace it."
  exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

# Subject Alternative Names matter more than the CN, which modern browsers ignore entirely. Both
# hostnames are needed: "localhost" for a browser on the host, and "clickkart-api-gateway" for
# any container that reaches the Gateway by its compose service name.
cat > "${TMP_DIR}/openssl.cnf" <<'CONF'
[req]
distinguished_name = dn
x509_extensions    = v3_req
prompt             = no

[dn]
CN = localhost
O  = ClickKart
C  = IN

[v3_req]
basicConstraints = critical, CA:FALSE
keyUsage         = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName   = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = clickkart-api-gateway
IP.1  = 127.0.0.1
CONF

openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout "${TMP_DIR}/gateway.key" \
  -out    "${TMP_DIR}/gateway.crt" \
  -days   "${DAYS}" \
  -config "${TMP_DIR}/openssl.cnf" 2>/dev/null

# PKCS12 rather than JKS: JKS is proprietary and deprecated since Java 9, and Spring Boot reads
# PKCS12 without extra configuration.
openssl pkcs12 -export \
  -in     "${TMP_DIR}/gateway.crt" \
  -inkey  "${TMP_DIR}/gateway.key" \
  -name   gateway \
  -out    "${KEYSTORE}" \
  -passout env:TLS_KEYSTORE_PASSWORD 2>/dev/null

chmod 600 "${KEYSTORE}"

echo "Wrote ${KEYSTORE} (self-signed, valid ${DAYS} days)."
echo "It is gitignored. Set TLS_KEYSTORE_PASSWORD in .env so the Gateway can read it."
