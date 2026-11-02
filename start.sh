#!/bin/bash
set -Eeuo pipefail

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

# shellcheck source=/dev/null
source .env

if [[ -n "$SNOW_ACCOUNT" && -n "$SNOW_USER" && -n "$SNOW_PAT" ]]; then
  echo "Generating SNOW_CONFIG_B64 from .env variables..."
  SNOW_CONFIG=$(cat <<EOF
[connections.${CONNECTION_NAME}]
account = "${SNOW_ACCOUNT}"
user = "${SNOW_USER}"
role = "${SNOW_ROLE:-CICD}"
database = "${SNOW_DATABASE:-DATAOPS}"
schema = "${SNOW_SCHEMA:-IOT_RAW_V001}"
warehouse = "${SNOW_WAREHOUSE:-MD_TEST_WH}"
authenticator = "programmatic_access_token"
token = "${SNOW_PAT}"
EOF
)
  SNOW_CONFIG_B64=$(echo "$SNOW_CONFIG" | base64 | tr -d '\n')
  export SNOW_CONFIG_B64
  echo "SNOW_CONFIG_B64 generated for connection: $CONNECTION_NAME"
elif [[ -f SNOW_CONFIG_B64 ]]; then
  echo "Using existing SNOW_CONFIG_B64 file..."
  SNOW_CONFIG_B64=$(cat SNOW_CONFIG_B64)
  export SNOW_CONFIG_B64
else
  echo "WARNING: No Snowflake credentials found. Set SNOW_ACCOUNT/SNOW_USER/SNOW_PAT in .env or provide SNOW_CONFIG_B64 file."
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
PROFILES=()
if [[ "${1:-}" == "--with-observability" ]]; then
  PROFILES=(--profile observability)
  export OTEL_EXPORTER_OTLP_ENDPOINT="jaeger:4317"
  echo "Observability enabled: Jaeger UI on http://localhost:16686"
fi
docker compose --env-file .env ${PROFILES[@]+"${PROFILES[@]}"} up -d --wait --remove-orphans
docker compose --env-file .env ${PROFILES[@]+"${PROFILES[@]}"} ps
echo "Logs: docker compose logs -f [service]"
