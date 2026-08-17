#!/usr/bin/env bash
#
# Copies the generated keystore into the named volume the Gateway mounts.
#
#   ./scripts/generate-dev-tls.sh      # creates certs/gateway-keystore.p12
#   ./scripts/seed-gateway-certs.sh    # puts it where the container can read it
#
# Why a volume and a copy rather than a bind mount of ./certs: Docker Desktop refuses to
# bind-mount a path on a drive that is not in its File Sharing list, and this project lives on D:.
# `docker cp` streams the file over the Docker API, so it works regardless of that setting.
#
# The key still never enters an image. That is the property worth keeping - images get pushed to
# registries, volumes stay on the host.

set -euo pipefail

VOLUME="${GATEWAY_CERT_VOLUME:-clickkart-gateway-certs}"
KEYSTORE="${KEYSTORE:-certs/gateway-keystore.p12}"
SEEDER="clickkart-cert-seeder"

[[ -f "${KEYSTORE}" ]] || {
  echo "${KEYSTORE} not found. Run scripts/generate-dev-tls.sh first." >&2
  exit 1
}

docker volume create "${VOLUME}" >/dev/null

# A stopped container is enough: `docker cp` does not require it to be running, and this way
# nothing is executed inside it.
docker rm -f "${SEEDER}" >/dev/null 2>&1 || true
docker create --name "${SEEDER}" -v "${VOLUME}":/app/certs alpine:3 true >/dev/null
trap 'docker rm -f "${SEEDER}" >/dev/null 2>&1 || true' EXIT

docker cp "${KEYSTORE}" "${SEEDER}":/app/certs/gateway-keystore.p12

echo "Seeded ${VOLUME} with $(basename "${KEYSTORE}")."
echo "Recreate the Gateway for it to pick the keystore up."
