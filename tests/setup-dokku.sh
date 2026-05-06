#!/usr/bin/env bash
set -eo pipefail

DOKKU_TAG="${DOKKU_TAG:-0.37.10}"
CONTAINER_NAME="dokku-generic-test"
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$(docker container inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null)" == "running" ]]; then
  echo "Dokku already running ($CONTAINER_NAME)"
  exit 0
fi

docker container rm -f "$CONTAINER_NAME" 2>/dev/null || true

docker container run -d \
  --name "$CONTAINER_NAME" \
  --privileged \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PLUGIN_DIR":/plugin-source:ro \
  -e DOKKU_HOSTNAME=dokku.test \
  "dokku/dokku:$DOKKU_TAG"

echo "Waiting for dokku to be ready..."
for _ in $(seq 1 30); do
  if docker exec "$CONTAINER_NAME" dokku version >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

# Install plugin from mounted source
docker exec "$CONTAINER_NAME" bash -c '
  set -e
  rm -rf /var/lib/dokku/plugins/available/generic
  cp -r /plugin-source /var/lib/dokku/plugins/available/generic
  dokku plugin:enable generic
  dokku plugin:install-dependencies --core
'

echo "Dokku ready: $CONTAINER_NAME"
echo "Run tests with: docker exec $CONTAINER_NAME bats /var/lib/dokku/plugins/available/generic/tests/service_*.bats"
