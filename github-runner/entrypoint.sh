#!/bin/bash
# -----------------------------------------------------------------------------
# Ephemeral GitHub Actions runner: registers, runs exactly one job, exits.
# Docker (restart: always) then starts a fresh registration, so a rebuild or
# restart never leaves queued jobs bound to a stale runner session.
#
# SonarQube token + rules are prepared once by the sonar-init service; the
# token is shared read-only via /sonar/.sonar_env.
# -----------------------------------------------------------------------------
set -euo pipefail

GH_TOKEN=${ACCESS_TOKEN:-}
GITHUB_OWNER=${GITHUB_OWNER:-}
GITHUB_REPO=${GITHUB_REPO:-}
RUNNER_SCOPE=${RUNNER_SCOPE:-repo}
RUNNER_NAME=${RUNNER_NAME:-"runner-$(hostname)"}
RUNNER_LABELS=${RUNNER_LABELS:-}

if [[ -z "$GH_TOKEN" || -z "$GITHUB_OWNER" ]]; then
  echo "ERROR: ACCESS_TOKEN and GITHUB_OWNER must be set"; exit 1
fi
if [[ "$RUNNER_SCOPE" == "org" ]]; then
  API_BASE="https://api.github.com/orgs/${GITHUB_OWNER}"
  CONFIG_URL="https://github.com/${GITHUB_OWNER}"
else
  [[ -n "$GITHUB_REPO" ]] || { echo "ERROR: GITHUB_REPO must be set for repo-level runners"; exit 1; }
  API_BASE="https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}"
  CONFIG_URL="https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}"
fi

cd /home/docker/actions-runner

[[ -d /home/docker/sql-report-vol ]] && { sudo chown -R docker:docker /home/docker/sql-report-vol || true; }
[[ -f /sonar/.sonar_env ]] && ln -sf /sonar/.sonar_env "$HOME/.sonar_env"
[[ -n "${SNOW_CONFIG_B64:-}" ]] && bash /usr/local/bin/snowflake-config-setup.sh

gh_token() {  # $1 = registration-token | remove-token
  curl -sf -X POST -H "Authorization: token ${GH_TOKEN}" -H "Accept: application/vnd.github+json" \
    "${API_BASE}/actions/runners/$1" | jq -r .token
}

# Deregister if stopped while idle (an ephemeral runner that ran a job is
# already removed by GitHub; the call then simply fails and is ignored).
cleanup() {
  echo "Stopping runner ${RUNNER_NAME}..."
  if [[ -n "${RUNNER_PID:-}" ]]; then kill "$RUNNER_PID" 2>/dev/null || true; fi
  if [[ -f .runner ]]; then
    ./config.sh remove --token "$(gh_token remove-token)" >/dev/null 2>&1 || true
  fi
  exit 0
}
trap cleanup INT TERM

# Local leftovers from a previous ephemeral run in this same container.
rm -f .runner .credentials .credentials_rsaparams

REG_TOKEN=$(gh_token registration-token || true)
[[ -n "$REG_TOKEN" && "$REG_TOKEN" != "null" ]] || { echo "ERROR: failed to get registration token"; exit 1; }

./config.sh --url "$CONFIG_URL" --token "$REG_TOKEN" --name "$RUNNER_NAME" \
  ${RUNNER_LABELS:+--labels "$RUNNER_LABELS"} --ephemeral --unattended --replace

echo "Starting ephemeral runner ${RUNNER_NAME}..."
./run.sh &
RUNNER_PID=$!
wait "$RUNNER_PID"
