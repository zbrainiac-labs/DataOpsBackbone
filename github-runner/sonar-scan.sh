#!/bin/bash
set -Eeuo pipefail
LIB="$(dirname "${BASH_SOURCE[0]}")/lib.sh"; [[ -f "$LIB" ]] || LIB=/usr/local/bin/lib.sh
# shellcheck source=/dev/null
source "$LIB"

if [[ -z "${SONAR_TOKEN:-}" && -f "$HOME/.sonar_env" ]]; then
  # shellcheck source=/dev/null
  source "$HOME/.sonar_env"
fi

SONAR_TOKEN="${SONAR_TOKEN:?Missing SONAR_TOKEN}"
[[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::add-mask::$SONAR_TOKEN"
PROJECT_KEY="${PROJECT_KEY:?Missing PROJECT_KEY}"
SONAR_HOST="${SONAR_HOST:-http://sonarqube:9000}"

SONAR_SCANNER="/usr/local/sonar-scanner/bin/sonar-scanner"

log_info "Checking if project '$PROJECT_KEY' exists in SonarQube..."
RESPONSE=$(curl -s -u "$SONAR_TOKEN:" "$SONAR_HOST/api/projects/search")

if echo "$RESPONSE" | jq -e '.components? // [] | any(.key == "'"$PROJECT_KEY"'")' > /dev/null; then
  log_info "✅ Project '$PROJECT_KEY' already exists."
else
  log_info "➕ Project '$PROJECT_KEY' not found. Creating it..."
  CREATE_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -u "$SONAR_TOKEN:" -X POST "$SONAR_HOST/api/projects/create" \
    -d "name=$PROJECT_KEY" \
    -d "project=$PROJECT_KEY")

  if [ "$CREATE_RESPONSE" -eq 200 ]; then
    log_info "✅ Successfully created project '$PROJECT_KEY'."
  elif [ "$CREATE_RESPONSE" -eq 400 ]; then
    log_info "Project '$PROJECT_KEY' already exists. Continuing..."
  else
    log_error "Failed to create project. HTTP code: $CREATE_RESPONSE"
    exit 1
  fi
fi

if [[ -n "${GITHUB_WORKSPACE:-}" ]]; then
  PROJECT_BASE_DIR="$GITHUB_WORKSPACE"
elif [[ -f /.dockerenv ]] || grep -qE '/docker/|/lxc/' /proc/1/cgroup 2>/dev/null; then
  PROJECT_BASE_DIR="/home/docker/actions-runner/_work/$PROJECT_KEY/$PROJECT_KEY"
elif [[ "$(uname)" == "Darwin" ]]; then
  PROJECT_BASE_DIR="${BASE_WORKSPACE:-$HOME/workspace}/$PROJECT_KEY"
else
  PROJECT_BASE_DIR="$(pwd)"
fi

EXTRA_ARGS=()
SQLFLUFF_ISSUES="$PROJECT_BASE_DIR/sqlfluff_issues.json"
if [[ -f "$SQLFLUFF_ISSUES" ]]; then
  log_info "SQLFluff issues found: $SQLFLUFF_ISSUES"
  EXTRA_ARGS+=("-Dsonar.externalIssuesReportPaths=$SQLFLUFF_ISSUES")
fi

SONAR_TEST_REPORT="${PROJECT_BASE_DIR}/sonar_test_report.xml"
if [[ -f "$SONAR_TEST_REPORT" ]]; then
  log_info "Test execution report found: $SONAR_TEST_REPORT"
  EXTRA_ARGS+=("-Dsonar.testExecutionReportPaths=$SONAR_TEST_REPORT")
fi

log_info "Running sonar-scanner..."
PROJECT_VERSION="${PROJECT_VERSION:-$(git -C "$PROJECT_BASE_DIR" describe --tags --always 2>/dev/null || echo 'unknown')}"

# DCM projects: scan a copy with Jinja placeholders neutralized so the AST-based
# SQL Code Checker can parse it (#45). The checkout itself is never modified
# (under act it can be the developer's working copy); report-task.txt is copied
# back for sonar-quality-gate.sh. File paths and line numbers are unchanged.
SCAN_DIR="$PROJECT_BASE_DIR"
NEUTRALIZE="$(dirname "${BASH_SOURCE[0]}")/neutralize_jinja.py"
[[ -f "$NEUTRALIZE" ]] || NEUTRALIZE=/usr/local/bin/neutralize_jinja.py
if grep -qsE "^type:[[:space:]]*['\"]?DCM_PROJECT" "$PROJECT_BASE_DIR/manifest.yml" && [[ -f "$NEUTRALIZE" ]]; then
  SCAN_DIR=$(mktemp -d)
  trap 'rm -rf "$SCAN_DIR"' EXIT
  tar -C "$PROJECT_BASE_DIR" --exclude=./.git --exclude=./.scannerwork --exclude=./node_modules -cf - . | tar -C "$SCAN_DIR" -xf -
  log_info "DCM project: $(python3 "$NEUTRALIZE" "$SCAN_DIR")"
  EXTRA_ARGS=("${EXTRA_ARGS[@]//$PROJECT_BASE_DIR/$SCAN_DIR}")
fi

"$SONAR_SCANNER" \
  -Dsonar.projectKey="$PROJECT_KEY" \
  -Dsonar.projectBaseDir="$SCAN_DIR" \
  -Dsonar.projectVersion="$PROJECT_VERSION" \
  -Dsonar.host.url="$SONAR_HOST" \
  -Dsonar.scm.disabled=true \
  -Dsonar.sources=. \
  -Dsonar.text.inclusions="**/*.sql,**/*.json" \
  -Dsonar.exclusions=".git/**,**/venv/**,**/node_modules/**,**/__pycache__/**,**/*.md,**/*.csv,**/*.yml,**/*.yaml,**/*.ipynb,**/*.sqltest,**/.DS_Store,**/*.p8,**/*.pub,**/*.pem,**/*.js,**/*.css,**/*.html,**/*.map" \
  -Dsonar.sourceEncoding="UTF-8" \
  "${EXTRA_ARGS[@]}" \
  -Dsonar.token="$SONAR_TOKEN"

if [[ "$SCAN_DIR" != "$PROJECT_BASE_DIR" && -d "$SCAN_DIR/.scannerwork" ]]; then
  rm -rf "$PROJECT_BASE_DIR/.scannerwork"
  cp -R "$SCAN_DIR/.scannerwork" "$PROJECT_BASE_DIR/.scannerwork"
fi
