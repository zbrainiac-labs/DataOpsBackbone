#!/bin/bash
set -Eeuo pipefail

# ============================================================
# E2E test: runs the full DataOps pipeline inside the Docker
# runner against a real consumer repo and live Snowflake.
#
# Prerequisites:
#   - .env file with SNOW_ACCOUNT, SNOW_USER, SNOW_PAT
#   - Consumer repo cloned locally (e.g. mother-of-all-Projects)
#
# Usage:
#   ./github-runner/e2e-test.sh [consumer-repo-path]
# ============================================================

CONSUMER_REPO="${1:-}"
if [[ -z "$CONSUMER_REPO" ]]; then
  echo "Usage: $0 <path-to-consumer-repo>"
  echo "Example: $0 ../mother-of-all-Projects"
  exit 1
fi

if [[ ! -d "$CONSUMER_REPO" ]]; then
  echo "ERROR: Consumer repo not found at: $CONSUMER_REPO"
  exit 1
fi

CONSUMER_REPO="$(cd "$CONSUMER_REPO" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "============================================"
echo "  DataOps E2E Test"
echo "============================================"
echo "  Consumer repo:  $CONSUMER_REPO"
echo "  Backbone:       $PROJECT_ROOT"
echo "============================================"

# --- Phase 1: Build Docker images ---
echo ""
echo "[Phase 1] Building Docker images..."
cd "$PROJECT_ROOT"
source .env

ARCH=$(uname -m)
case "$ARCH" in
  x86_64)    PLATFORM="linux/amd64"; TARGETARCH="amd64" ;;
  arm64|*)   PLATFORM="linux/arm64"; TARGETARCH="arm64" ;;
esac

docker build --platform="$PLATFORM" --build-arg TARGETARCH="$TARGETARCH" \
  -t brainiac/local-github-runner -f github-runner/Dockerfile github-runner
echo "[Phase 1] Runner image built."

docker build --platform="$PLATFORM" --build-arg TARGETARCH="$TARGETARCH" \
  -t brainiac/sonarqube ./sonarqube
echo "[Phase 1] SonarQube image built."

# --- Phase 2: Start stack ---
echo ""
echo "[Phase 2] Starting Docker Compose stack..."
docker compose --env-file .env up -d

echo "Waiting for SonarQube to be ready..."
STATUS=""
for i in $(seq 1 60); do
  STATUS=$(curl -sf http://localhost:9000/api/system/status 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || true)
  if [[ "$STATUS" == "UP" ]]; then
    echo "SonarQube is UP."
    break
  fi
  sleep 5
done
if [[ "$STATUS" != "UP" ]]; then
  echo "ERROR: SonarQube not ready after 5 minutes."
  docker compose logs sonarqube
  docker compose down
  exit 1
fi

# --- Phase 3: Run pipeline ---
echo ""
echo "[Phase 3] Running DataOps pipeline..."

# Determine Snowflake connection: use local CLI config or generate from .env
LOCAL_SNOW_DIR="$HOME/.snowflake"
LOCAL_SNOW_CONFIG="$LOCAL_SNOW_DIR/config.toml"
LOCAL_SNOW_CONNECTIONS="$LOCAL_SNOW_DIR/connections.toml"
E2E_CONNECTION_NAME="${CONNECTION_NAME:-zs28104-e2e}"

# Check both config files for the connection
FOUND_IN=""
if [[ -f "$LOCAL_SNOW_CONFIG" ]] && grep -q "\[connections\.$E2E_CONNECTION_NAME\]" "$LOCAL_SNOW_CONFIG" 2>/dev/null; then
  FOUND_IN="config"
elif [[ -f "$LOCAL_SNOW_CONNECTIONS" ]] && grep -q "\[$E2E_CONNECTION_NAME\]" "$LOCAL_SNOW_CONNECTIONS" 2>/dev/null; then
  FOUND_IN="connections"
fi

if [[ -n "$FOUND_IN" ]]; then
  echo "Using local Snowflake CLI connection: $E2E_CONNECTION_NAME"
  USE_LOCAL_CONFIG=true
else
  echo "Generating Snowflake config from .env..."
  USE_LOCAL_CONFIG=false
  SNOW_CONFIG=$(cat <<EOF
[connections.${E2E_CONNECTION_NAME}]
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
  export SNOW_CONFIG_B64
  SNOW_CONFIG_B64=$(echo "$SNOW_CONFIG" | base64 | tr -d '\n')
fi

# Copy consumer repo files into the runner container
echo "Copying consumer repo into runner container..."
docker compose exec -T runner1 mkdir -p /tmp/e2e-output
docker compose cp "$CONSUMER_REPO/." runner1:/tmp/e2e-output/

# Find the test file (look for .sqltest in the consumer repo, fall back to built-in)
CONSUMER_TEST_FILE=$(find "$CONSUMER_REPO" -name '*.sqltest' -type f 2>/dev/null | head -1 || true)
if [[ -n "$CONSUMER_TEST_FILE" ]]; then
  # Derive the relative path within the consumer repo
  RELATIVE_TEST_PATH="${CONSUMER_TEST_FILE#$CONSUMER_REPO/}"
  CONTAINER_TEST_FILE="/tmp/e2e-output/$RELATIVE_TEST_PATH"
else
  CONTAINER_TEST_FILE="/usr/local/bin/tests.sqltest"
fi

# Setup Snowflake connection inside the container
if [[ "$USE_LOCAL_CONFIG" == "true" ]]; then
  echo "Copying local Snowflake config into runner (found in $FOUND_IN.toml)..."
  docker compose exec -T runner1 mkdir -p /home/docker/.snowflake
  # Copy both config files if they exist
  if [[ -f "$LOCAL_SNOW_CONFIG" ]]; then
    docker compose cp "$LOCAL_SNOW_CONFIG" runner1:/home/docker/.snowflake/config.toml
    docker compose exec -T -u root runner1 chown docker:docker /home/docker/.snowflake/config.toml
    docker compose exec -T -u root runner1 chmod 600 /home/docker/.snowflake/config.toml
  fi
  if [[ -f "$LOCAL_SNOW_CONNECTIONS" ]]; then
    docker compose cp "$LOCAL_SNOW_CONNECTIONS" runner1:/home/docker/.snowflake/connections.toml
    docker compose exec -T -u root runner1 chown docker:docker /home/docker/.snowflake/connections.toml
    docker compose exec -T -u root runner1 chmod 600 /home/docker/.snowflake/connections.toml
  fi
  # Copy private key if referenced in the connection
  CONN_FILE="$LOCAL_SNOW_DIR/${FOUND_IN}.toml"
  PRIVATE_KEY_FILE=$(grep -A15 "\[$E2E_CONNECTION_NAME\]" "$CONN_FILE" | grep 'private_key_file' | head -1 | sed 's/.*= *"\(.*\)"/\1/' || true)
  if [[ -n "$PRIVATE_KEY_FILE" && -f "$PRIVATE_KEY_FILE" ]]; then
    echo "Copying private key into runner..."
    docker compose cp "$PRIVATE_KEY_FILE" runner1:/home/docker/.snowflake/rsa_key.p8
    docker compose exec -T -u root runner1 chown docker:docker /home/docker/.snowflake/rsa_key.p8
    docker compose exec -T -u root runner1 chmod 600 /home/docker/.snowflake/rsa_key.p8
    # Rewrite the path inside the container
    docker compose exec -T -u root runner1 sed -i "s|$PRIVATE_KEY_FILE|/home/docker/.snowflake/rsa_key.p8|g" /home/docker/.snowflake/${FOUND_IN}.toml
  fi
else
  echo "Decoding Snowflake config..."
  docker compose exec -T runner1 bash -c "
    export SNOW_CONFIG_B64='$SNOW_CONFIG_B64'
    bash /usr/local/bin/github-runner_v1.sh
  "
fi

docker compose exec -T runner1 bash -c "
  export CONNECTION_NAME='$E2E_CONNECTION_NAME'
  export SOURCE_DATABASE='${SNOW_DATABASE:-DATAOPS}'
  export SOURCE_SCHEMA='${SNOW_SCHEMA:-IOT_RAW_V001}'
  export PROJECT_KEY='$(basename "$CONSUMER_REPO")'
  export DCM_PROJECT_IDENTIFIER='${DCM_PROJECT_IDENTIFIER:-DATAOPS.IOT_RAW_V001.MOTHER_OF_ALL_PROJECTS}'
  export DCM_TARGET='${DCM_TARGET:-DEV}'
  export RELEASE_NUM='e2e-test'
  export TEST_FILE='$CONTAINER_TEST_FILE'
  export FAKE_RUN='false'

  echo 'Running dependencies extraction...'
  bash /usr/local/bin/snowflake-extract-dependencies_v1.sh \
    --SOURCE_DATABASE=\$SOURCE_DATABASE \
    --SOURCE_SCHEMA=\$SOURCE_SCHEMA \
    --OUTPUT_DIR=/tmp/e2e-output \
    --CONNECTION_NAME=\$CONNECTION_NAME

  echo 'Running DCM deploy...'
  bash /usr/local/bin/snowflake-deploy-dcm_v1.sh \
    --PROJECT_IDENTIFIER=\$DCM_PROJECT_IDENTIFIER \
    --CONNECTION_NAME=\$CONNECTION_NAME \
    --TARGET=\$DCM_TARGET \
    --ALIAS=e2e-test \
    --PROJECT_DIR=/tmp/e2e-output

  echo 'Running SQLFluff scan...'
  bash /usr/local/bin/sqlfluff-to-sonar.sh /tmp/e2e-output /tmp/e2e-output/sqlfluff_issues.json

  echo 'Running SonarQube scan...'
  if [[ -f \$HOME/.sonar_env ]]; then
    source \$HOME/.sonar_env
  fi
  export PROJECT_KEY=\$PROJECT_KEY
  export SONAR_HOST='http://sonarqube:9000'
  export PROJECT_VERSION='e2e-test'
  # sonar-scanner_v2.sh expects files under the runner work dir; symlink to our e2e output
  SCAN_DIR=\"/home/docker/actions-runner/_work/\$PROJECT_KEY/\$PROJECT_KEY\"
  mkdir -p \"\$(dirname \$SCAN_DIR)\"
  ln -sfn /tmp/e2e-output \"\$SCAN_DIR\"
  bash /usr/local/bin/sonar-scanner_v2.sh

  echo 'Running SQL validation...'
  bash /usr/local/bin/sql_validation_v4.sh \
    --CLONE_SCHEMA=\$SOURCE_SCHEMA \
    --CLONE_DATABASE=\$SOURCE_DATABASE \
    --RELEASE_NUM=e2e-test \
    --CONNECTION_NAME=\$CONNECTION_NAME \
    --TEST_FILE=\$TEST_FILE \
    --FAKE_RUN=false
"
PIPELINE_EXIT=$?

# --- Phase 4: Cleanup ---
# echo ""
# echo "[Phase 4] Tearing down stack..."
# docker compose down

# --- Result ---
echo ""
if [[ $PIPELINE_EXIT -eq 0 ]]; then
  echo "============================================"
  echo "  E2E TEST PASSED"
  echo "============================================"
else
  echo "============================================"
  echo "  E2E TEST FAILED (exit code: $PIPELINE_EXIT)"
  echo "============================================"
  exit 1
fi
