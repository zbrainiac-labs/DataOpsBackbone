#!/bin/bash
# -----------------------------------------------------------------------------
# Scan this repo with the local SonarQube and fail on BLOCKER/CRITICAL issues.
# Uses the shared token from the sonar-init volume; config: sonar-project.properties
#
# Usage: bash local-ci/sonar-self-scan.sh
# -----------------------------------------------------------------------------
set -Eeuo pipefail

BACKBONE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NETWORK=$(docker network ls --format '{{.Name}}' | grep -m1 'sonarnet$' || true)
VOLUME=$(docker volume ls --format '{{.Name}}' | grep -m1 'sonar_env$' || true)
[[ -n "$NETWORK" && -n "$VOLUME" ]] || { echo "ERROR: stack not running -- run ./start.sh first"; exit 1; }

docker run --rm --network "$NETWORK" \
  -v "$VOLUME:/sonar:ro" -v "$BACKBONE:/src" -w /src \
  --user root --entrypoint bash brainiac/local-github-runner -c '
    set -Eeuo pipefail
    source /sonar/.sonar_env
    git config --global --add safe.directory /src
    pip install -q --disable-pip-version-check --root-user-action=ignore pytest pytest-cov regex >/dev/null 2>&1
    python3 -m pytest -q -p no:cacheprovider --cov=github-runner --cov=sqlfluff --cov-report=xml:/tmp/coverage.xml tests | tail -n 1
    H=http://sonarqube:9000
    sonar-scanner -Dsonar.host.url=$H -Dsonar.token="$SONAR_TOKEN" \
      -Dsonar.python.coverage.reportPaths=/tmp/coverage.xml \
      -Dsonar.working.directory=/tmp/.scannerwork -Dsonar.qualitygate.wait=true \
      2>&1 | grep -E "ERROR|ANALYSIS SUCCESSFUL|QUALITY GATE|EXECUTION" || true
    ISSUES=$(curl -sf -u "$SONAR_TOKEN:" \
      "$H/api/issues/search?componentKeys=DataOpsBackbone-local&resolved=false&severities=BLOCKER,CRITICAL&ps=500")
    COUNT=$(jq ".total" <<<"$ISSUES")
    jq -r ".issues[] | [.severity, .rule, (.component|sub(\"^[^:]*:\";\"\")), (.line//0|tostring), .message] | @tsv" <<<"$ISSUES"
    echo "BLOCKER+CRITICAL issues: $COUNT"
    [[ "$COUNT" -eq 0 ]]
  '
