#!/bin/bash
# Usage: sqlfluff-to-sonar.sh [PROJECT_DIR] [OUTPUT_FILE] [FAIL_THRESHOLD]
#   FAIL_THRESHOLD > 0: exit 1 when CRITICAL issues >= threshold (0 = never fail)
set +e
LIB="$(dirname "${BASH_SOURCE[0]}")/lib.sh"; [[ -f "$LIB" ]] || LIB=/usr/local/bin/lib.sh
# shellcheck source=/dev/null
source "$LIB"
set -u

PROJECT_DIR="${1:-.}"
OUTPUT_FILE="${2:-sqlfluff_issues.json}"
FAIL_THRESHOLD="${3:-0}"

log_info "Running SQLFluff on $PROJECT_DIR..."

SQLFLUFF_CONFIG="/usr/local/bin/sqlfluff_sonar.cfg"
if [[ ! -f "$SQLFLUFF_CONFIG" ]]; then
  SQLFLUFF_CONFIG="$(dirname "$0")/sqlfluff_sonar.cfg"
fi

TMPJSON=$(mktemp /tmp/sqlfluff_raw_XXXXXX.json)

sqlfluff lint "$PROJECT_DIR" \
  --dialect snowflake \
  --config "$SQLFLUFF_CONFIG" \
  --format json \
  --ignore-local-config \
  > "$TMPJSON" 2>/dev/null || true

if [[ ! -s "$TMPJSON" ]]; then
  echo '{"issues":[]}' > "$OUTPUT_FILE"
  log_info "No SQLFluff issues found."
  rm -f "$TMPJSON"
  exit 0
fi

CONVERTER="/usr/local/bin/sqlfluff_to_sonar.py"
if [[ ! -f "$CONVERTER" ]]; then
  CONVERTER="$(dirname "$0")/sqlfluff_to_sonar.py"
fi

python3 "$CONVERTER" "$TMPJSON" "$OUTPUT_FILE"
rm -f "$TMPJSON"

if (( FAIL_THRESHOLD > 0 )); then
  CRITICAL=$(jq '[.issues[]? | select(.severity == "CRITICAL")] | length' "$OUTPUT_FILE" 2>/dev/null || echo 0)
  log_info "::notice::SQLFluff critical violations: $CRITICAL (threshold: $FAIL_THRESHOLD)"
  if (( CRITICAL >= FAIL_THRESHOLD )); then
    log_error "SQLFluff critical violations ($CRITICAL) exceed threshold ($FAIL_THRESHOLD)"
    exit 1
  fi
fi
exit 0
