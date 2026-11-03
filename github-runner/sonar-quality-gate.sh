#!/bin/bash
# -----------------------------------------------------------------------------
# Wait for the SonarQube analysis of this build and check its Quality Gate.
# Reads SONAR_TOKEN from ~/.sonar_env so the token never enters the job env.
#
# Usage: sonar-quality-gate.sh [REPORT_TASK_FILE] [TIMEOUT_SECONDS]
# Exit:  0 = gate OK, 1 = gate failed / error, 2 = timeout
# -----------------------------------------------------------------------------
set -Eeuo pipefail
LIB="$(dirname "${BASH_SOURCE[0]}")/lib.sh"; [[ -f "$LIB" ]] || LIB=/usr/local/bin/lib.sh
# shellcheck source=/dev/null
source "$LIB"

REPORT="${1:-.scannerwork/report-task.txt}"
TIMEOUT="${2:-300}"

if [[ -z "${SONAR_TOKEN:-}" && -f "$HOME/.sonar_env" ]]; then
  # shellcheck source=/dev/null
  source "$HOME/.sonar_env"
fi
SONAR_TOKEN="${SONAR_TOKEN:?Missing SONAR_TOKEN}"
[[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::add-mask::$SONAR_TOKEN"

[[ -f "$REPORT" ]] || { echo "::error::$REPORT not found -- did sonar-scanner run?"; exit 1; }
SERVER_URL=$(grep -m1 '^serverUrl=' "$REPORT" | cut -d= -f2-)
CE_TASK_URL=$(grep -m1 '^ceTaskUrl=' "$REPORT" | cut -d= -f2-)

api() { curl -sf -u "$SONAR_TOKEN:" "$1"; }

log_info "Waiting for analysis task: $CE_TASK_URL"
DEADLINE=$(( $(date +%s) + TIMEOUT ))
while :; do
  TASK=$(api "$CE_TASK_URL")
  STATUS=$(jq -r '.task.status' <<<"$TASK")
  case "$STATUS" in
    SUCCESS) break ;;
    FAILED|CANCELED) echo "::error::SonarQube analysis $STATUS"; exit 1 ;;
  esac
  (( $(date +%s) < DEADLINE )) || { echo "::error::Timed out after ${TIMEOUT}s waiting for analysis"; exit 2; }
  sleep 5
done

ANALYSIS_ID=$(jq -r '.task.analysisId' <<<"$TASK")
GATE=$(api "$SERVER_URL/api/qualitygates/project_status?analysisId=$ANALYSIS_ID" | jq -r '.projectStatus.status')
echo "quality-gate-status=$GATE" >> "${GITHUB_OUTPUT:-/dev/null}"
log_info "Quality Gate status: $GATE"

if [[ "$GATE" == "OK" ]]; then
  exit 0
fi
log_error "Quality Gate status: $GATE"
exit 1
