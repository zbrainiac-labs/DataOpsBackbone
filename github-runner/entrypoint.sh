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

# Remove offline registrations left behind by earlier containers of this pool
# (killed/recreated containers can't always deregister). Only touches runners
# named runner-* that carry our label, so other self-hosted runners are safe.
prune_offline_runners() {
  [[ -n "$RUNNER_LABELS" ]] || return 0
  local ids id
  ids=$(curl -sf -H "Authorization: token ${GH_TOKEN}" -H "Accept: application/vnd.github+json" \
    "${API_BASE}/actions/runners?per_page=100" \
    | jq -r --arg want "$RUNNER_LABELS" '.runners[]
        | select(.status == "offline" and (.name | startswith("runner-")) and any(.labels[]; .name == $want))
        | .id') || { echo "Could not list runners for pruning (skipped)"; return 0; }
  for id in $ids; do
    if curl -sf -o /dev/null -X DELETE -H "Authorization: token ${GH_TOKEN}" \
        -H "Accept: application/vnd.github+json" "${API_BASE}/actions/runners/${id}"; then
      echo "Pruned offline runner registration ${id}"
    fi
  done
}

# Deregister if stopped while idle (an ephemeral runner that ran a job is
# already removed by GitHub). One API call instead of `config.sh remove`, which
# can't finish once dumb-init has signalled the runner too. Leftovers from hard
# kills are pruned by the next runner start.
cleanup() {
  echo "Stopping runner ${RUNNER_NAME}..."
  local id
  id=$(grep -o '"agentId": *[0-9]*' .runner 2>/dev/null | grep -o '[0-9]*$' || true)  # .runner has a BOM -> no jq
  if [[ -n "$id" ]] && curl -sf -o /dev/null --max-time 5 -X DELETE -H "Authorization: token ${GH_TOKEN}" \
      -H "Accept: application/vnd.github+json" "${API_BASE}/actions/runners/${id}"; then
    echo "Deregistered runner ${RUNNER_NAME} (id ${id})"
  fi
  if [[ -n "${RUNNER_PID:-}" ]]; then kill "$RUNNER_PID" 2>/dev/null || true; fi
  exit 0
}
trap cleanup INT TERM

# Local leftovers from a previous ephemeral run in this same container.
rm -f .runner .credentials .credentials_rsaparams
prune_offline_runners

REG_TOKEN=$(gh_token registration-token || true)
[[ -n "$REG_TOKEN" && "$REG_TOKEN" != "null" ]] || { echo "ERROR: failed to get registration token"; exit 1; }

./config.sh --url "$CONFIG_URL" --token "$REG_TOKEN" --name "$RUNNER_NAME" \
  ${RUNNER_LABELS:+--labels "$RUNNER_LABELS"} --ephemeral --unattended --replace

echo "Starting ephemeral runner ${RUNNER_NAME}..."
./run.sh &
RUNNER_PID=$!
wait "$RUNNER_PID"
