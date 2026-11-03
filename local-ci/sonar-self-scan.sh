#!/bin/bash
# -----------------------------------------------------------------------------
# Scan this repo with the stack's SonarQube and fail on scanner errors, a
# failed quality gate, or BLOCKER/CRITICAL issues. Used locally and in CI.
# Uses the shared token from the sonar-init volume; config: sonar-project.properties
#
# Usage: bash local-ci/sonar-self-scan.sh
# Env:   SONAR_HOST (default http://sonarqube:9000), SONAR_PROJECT_KEY
#        (default DataOpsBackbone-local), RUNNER_IMAGE (default brainiac/local-github-runner)
# -----------------------------------------------------------------------------
set -Eeuo pipefail

BACKBONE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NETWORK=$(docker network ls --format '{{.Name}}' | grep -m1 'sonarnet$' || true)
VOLUME=$(docker volume ls --format '{{.Name}}' | grep -m1 'sonar_env$' || true)
[[ -n "$NETWORK" && -n "$VOLUME" ]] || { echo "ERROR: stack not running -- run ./start.sh first"; exit 1; }

docker run --rm --network "$NETWORK" \
  -v "$VOLUME:/sonar:ro" -v "$BACKBONE:/src" -w /src \
  -e H="${SONAR_HOST:-http://sonarqube:9000}" \
  -e KEY="${SONAR_PROJECT_KEY:-DataOpsBackbone-local}" \
  -e COVERAGE_FILE=/tmp/.coverage \
  --user root --entrypoint bash "${RUNNER_IMAGE:-brainiac/local-github-runner}" -c '
    set -Eeuo pipefail
    source /sonar/.sonar_env
    git config --global --add safe.directory /src
    # the image ships without pip; bootstrap it only in this throwaway container
    python3 -m ensurepip >/dev/null 2>&1
    python3 -m pip install -q --disable-pip-version-check --root-user-action=ignore pytest pytest-cov regex >/dev/null 2>&1
    python3 -m pytest -q -p no:cacheprovider --cov=github-runner --cov=sqlfluff --cov-report=xml:/tmp/coverage.xml tests | tail -n 1
    RC=0
    sonar-scanner -Dsonar.host.url="$H" -Dsonar.token="$SONAR_TOKEN" -Dsonar.projectKey="$KEY" \
      -Dsonar.python.coverage.reportPaths=/tmp/coverage.xml \
      -Dsonar.working.directory=/tmp/.scannerwork -Dsonar.qualitygate.wait=true \
      >/tmp/scanner.log 2>&1 || RC=$?
    grep -E "ERROR|ANALYSIS SUCCESSFUL|QUALITY GATE|EXECUTION" /tmp/scanner.log || true
    [[ "$RC" -eq 0 ]] || { echo "sonar-scanner failed (exit $RC)"; tail -n 40 /tmp/scanner.log; exit "$RC"; }
    ISSUES=$(curl -sf -u "$SONAR_TOKEN:" \
      "$H/api/issues/search?componentKeys=$KEY&resolved=false&severities=BLOCKER,CRITICAL&ps=500")
    COUNT=$(jq ".total" <<<"$ISSUES")
    jq -r ".issues[] | [.severity, .rule, (.component|sub(\"^[^:]*:\";\"\")), (.line//0|tostring), .message] | @tsv" <<<"$ISSUES"
    echo "BLOCKER+CRITICAL issues: $COUNT"
    [[ "$COUNT" -eq 0 ]]
  '
