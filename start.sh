#!/bin/bash
# Build the images locally and start the stack.
# Usage: ./start.sh [--no-observability]
#   --no-observability   do not start Jaeger; runners send no traces
set -Eeuo pipefail

OBSERVABILITY=true
for arg in "$@"; do
  case "$arg" in
    --no-observability) OBSERVABILITY=false ;;
    --with-observability) ;;  # old flag; tracing is now on by default
    -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

# Step 0: Clean up (optional)
# docker compose down -v --remove-orphans

# Detect architecture
ARCH=$(uname -m)
echo "Detected architecture: $ARCH"

case "$ARCH" in
  x86_64)
    PLATFORM="linux/amd64"
    TARGETARCH="amd64"
    ;;
  arm64|aarch64)
    PLATFORM="linux/arm64"
    TARGETARCH="arm64"
    ;;
  *)
    echo "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

# .env feeds docker compose (GitHub org/token, Postgres, SonarQube). Snowflake
# credentials are not passed to the runners: every pipeline job configures its
# own connection (OIDC, or the SNOW_CONFIG_B64 GitHub secret, see
# local-ci/snow-config.sh).
[[ -f .env ]] || { echo "Missing .env (see README: Configure .env)"; exit 1; }

echo "Building GitHub runner image for $PLATFORM..."
docker build \
  --platform=$PLATFORM \
  --build-arg TARGETARCH=$TARGETARCH \
  -t brainiac/local-github-runner \
  -f github-runner/Dockerfile \
  github-runner

echo "Building SonarQube image for $PLATFORM..."
docker build \
  --platform=$PLATFORM \
  --build-arg TARGETARCH=$TARGETARCH \
  -t brainiac/sonarqube \
  ./sonarqube

echo "Starting all services with docker compose (detached)..."
# Detached: the script exits once services are up/healthy instead of staying
# attached to the containers (previously one ./start.sh process per deploy).
UP_ARGS=()
if [[ "$OBSERVABILITY" == true ]]; then
  echo "Observability enabled: Jaeger UI on http://localhost:16686"
else
  export OTEL_EXPORTER_OTLP_ENDPOINT=""
  UP_ARGS=(--scale jaeger=0)
  docker compose --env-file .env rm -sf jaeger >/dev/null 2>&1 || true
  echo "Observability disabled"
fi
docker compose --env-file .env up -d --wait --remove-orphans ${UP_ARGS[@]+"${UP_ARGS[@]}"}
docker compose --env-file .env ps
echo "Logs: docker compose logs -f [service]"
