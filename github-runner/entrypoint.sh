#!/bin/bash
set -euo pipefail

# Basic environment vars
GH_TOKEN=${ACCESS_TOKEN:-}
GITHUB_OWNER=${GITHUB_OWNER:-}
GITHUB_REPO=${GITHUB_REPO:-}
RUNNER_NAME=${RUNNER_NAME:-"github-runner-$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)"}

echo "GITHUB_OWNER: ${GITHUB_OWNER}"
echo "GITHUB_REPO: ${GITHUB_REPO}"
echo "Runner name: ${RUNNER_NAME}"

cd /home/docker/actions-runner || { echo "ERROR: Runner directory not found"; exit 1; }

echo "🔧 Checking sql-report-vol ownership..."
if [ -d /home/docker/sql-report-vol ]; then
    sudo chown -R docker:docker /home/docker/sql-report-vol || echo "Could not chown volume"
else
    echo "Volume directory not found at runtime"
fi

if [[ -n "${SNOW_CONFIG_B64:-}" ]]; then
    echo "Setting up Snowflake config..."
    bash /usr/local/bin/github-runner_v1.sh
fi

if [[ -n "${SONAR_ADMIN_PASS:-}" ]]; then
    echo "Auto-generating SonarQube token..."
    bash /usr/local/bin/sonar-token-init.sh || echo "Sonar token init skipped"
    if [[ -f "$HOME/.sonar_env" ]]; then
        source "$HOME/.sonar_env"
    fi
fi
# Clean up runner on termination
cleanup() {
    echo "Caught termination signal. Cleaning up runner..."

    if [ -f .runner ]; then
        echo "Fetching removal token..."
        REMOVE_TOKEN=$(curl -s -X POST \
            -H "Authorization: token ${GH_TOKEN}" \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/actions/runners/remove-token" \
            | jq -r .token)

        if [[ -n "${REMOVE_TOKEN}" && "${REMOVE_TOKEN}" != "null" ]]; then
            ./config.sh remove --token "${REMOVE_TOKEN}" || echo "Runner removal failed or was already removed"
        else
            echo "Failed to get removal token; skipping removal"
        fi
    else
        echo "No runner config found; skipping removal"
    fi

    exit 0
}

trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# Validate required vars
if [[ -z "${GH_TOKEN}" || -z "${GITHUB_OWNER}" || -z "${GITHUB_REPO}" ]]; then
    echo "ERROR: ACCESS_TOKEN, GITHUB_OWNER, and GITHUB_REPO must be set"
    exit 1
fi

# Remove stale runner if it exists
if [ -f .runner ]; then
    echo "Runner already configured. Removing existing runner before re-registering..."
    REMOVE_TOKEN=$(curl -s -X POST \
        -H "Authorization: token ${GH_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/actions/runners/remove-token" \
        | jq -r .token)

    if [[ -n "${REMOVE_TOKEN}" && "${REMOVE_TOKEN}" != "null" ]]; then
        ./config.sh remove --token "${REMOVE_TOKEN}" || echo "Stale runner removal failed or already removed"
    else
        echo "Failed to get removal token; skipping stale removal"
    fi
fi

# Fetch registration token
echo "Fetching registration token..."
REG_TOKEN=$(curl -s -X POST \
    -H "Authorization: token ${GH_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/actions/runners/registration-token" \
    | jq -r .token)

if [[ -z "${REG_TOKEN}" || "${REG_TOKEN}" == "null" ]]; then
    echo "ERROR: Failed to retrieve registration token. Check credentials and permissions."
    exit 1
fi

echo "Registration token acquired. Configuring runner..."
./config.sh --url "https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}" \
            --token "${REG_TOKEN}" \
            --name "${RUNNER_NAME}" \
            --unattended --replace

# Start runner as PID 1
echo "Starting GitHub Actions runner..."

./run.sh > >(tee /tmp/runner-output.log) 2>&1 &
RUNNER_PID=$!

# Monitor for session conflict
( tail -n 0 -F /tmp/runner-output.log & echo $! >&3 ) 3>tail.pid | while read -r line; do
    echo "$line"
    if [[ "$line" == *"A session for this runner already exists."* ]]; then
        echo "❌ Detected session conflict. Killing runner process to force container restart..."
        kill "$RUNNER_PID" 2>/dev/null
        kill "$(cat tail.pid)" 2>/dev/null
        sleep 2
        exit 1
    fi
done

# Wait for runner process to finish (if no conflict triggered it)
wait "$RUNNER_PID"
