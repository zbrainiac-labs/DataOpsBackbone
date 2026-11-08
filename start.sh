#!/bin/bash
# Build the images locally and start the stack.
# Usage: ./start.sh [--no-observability]
#   --no-observability   do not start otel-collector/VictoriaTraces/VictoriaMetrics/Grafana; runners send no traces
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

OBS_SERVICES=(otel-collector victoriatraces victoriametrics grafana)

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

UP_ARGS=()
if [[ "$OBSERVABILITY" == true ]]; then
  GRAFANA_PASS=$(grep -m1 '^GRAFANA_ADMIN_PASSWORD=' .env | cut -d= -f2- || true)
  if [[ -z "$GRAFANA_PASS" || "$GRAFANA_PASS" == "admin" ]]; then
    echo "Set GRAFANA_ADMIN_PASSWORD in .env (not empty, not 'admin'), or use --no-observability"
    exit 1
  fi
else
  export OTEL_EXPORTER_OTLP_ENDPOINT=""
  # Compose interpolates the grafana service even when scaled to 0
  grep -q '^GRAFANA_ADMIN_PASSWORD=.' .env || export GRAFANA_ADMIN_PASSWORD=unused-observability-off
  for svc in "${OBS_SERVICES[@]}"; do UP_ARGS+=(--scale "$svc=0"); done
fi

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
if [[ "$OBSERVABILITY" == false ]]; then
  docker compose --env-file .env rm -sf "${OBS_SERVICES[@]}" >/dev/null 2>&1 || true
fi
docker compose --env-file .env up -d --wait --remove-orphans ${UP_ARGS[@]+"${UP_ARGS[@]}"}
docker compose --env-file .env ps

if [[ "$OBSERVABILITY" == true ]]; then
  # Warn only: tracing is fail-open, pipelines run without the backends
  bash local-ci/observability-smoke.sh --quick || true
  echo "Observability: Grafana on http://localhost:3000 (folder DataOps)"
  # The UI has no default-range setting (opens on 5 minutes); the link carries 7 days
  echo "Traces UI (last 7 days): http://127.0.0.1:10428/select/vmui/?#/?g0.range_input=7d&g0.relative_time=last_7_days&limit=5000"
else
  echo "Observability disabled"
fi
echo "Logs: docker compose logs -f [service]"
