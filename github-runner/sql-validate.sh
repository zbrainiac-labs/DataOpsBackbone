#!/bin/bash

# -----------------------------------------------------------------------------
# Snowflake SQL Validation using `snow` CLI
# Output: CTRF JSON (Common Test Report Format)
# -----------------------------------------------------------------------------
# Usage:
# ./sql-validate.sh \
#   --CLONE_SCHEMA=IOT_RAW_V001 \
#   --CLONE_DATABASE=DATAOPS \
#   --CONNECTION_NAME=zs28104-svc_cicd \
#   --TEST_FILE=./sqlunit/tests.sqltest
# -----------------------------------------------------------------------------

FAKE_RUN=false
RELEASE_NUM=""
WORKSPACE_DIR="$(pwd)"
set +e
LIB="$(dirname "${BASH_SOURCE[0]}")/lib.sh"; [[ -f "$LIB" ]] || LIB=/usr/local/bin/lib.sh
# shellcheck source=/dev/null
source "$LIB"
set -u

# --- Argument parsing ---
for ARG in "$@"; do
  case $ARG in
    --CLONE_DATABASE=*)
      CLONE_DATABASE="${ARG#*=}" ;;
    --CLONE_SCHEMA=*)
      CLONE_SCHEMA="${ARG#*=}" ;;
    --RELEASE_NUM=*)
      RELEASE_NUM="${ARG#*=}" ;;
    --CONNECTION_NAME=*)
      CONNECTION_NAME="${ARG#*=}" ;;
    --TEST_FILE=*)
      TEST_FILE="${ARG#*=}" ;;
    --FAKE_RUN=*)
      FAKE_RUN="${ARG#*=}" ;;
    *)
      log_error "Unknown argument: $ARG"
      log_info "Usage: $0 --CLONE_DATABASE=... --CLONE_SCHEMA=... --CONNECTION_NAME=... --TEST_FILE=... [--RELEASE_NUM=...] [--FAKE_RUN=...]"
      exit 1
      ;;
  esac
done

log_info "FAKE_RUN is set to: $FAKE_RUN"

# --- Validation ---
if [[ -z "${CLONE_SCHEMA:-}" || -z "${CLONE_DATABASE:-}" || -z "${CONNECTION_NAME:-}" || -z "${TEST_FILE:-}" ]]; then
  log_error "Missing required arguments."
  exit 1
fi

if [[ ! -f "$TEST_FILE" ]]; then
  log_error "Test file not found: $TEST_FILE"
  exit 1
fi

if [[ -n "$RELEASE_NUM" && "$RELEASE_NUM" != "0" ]]; then
  CLONE_SCHEMA_WITH_RELEASE="${CLONE_SCHEMA}_${RELEASE_NUM}"
else
  CLONE_SCHEMA_WITH_RELEASE="${CLONE_SCHEMA}"
fi
UTC_TIMESTAMP=$(date -u +"%Y-%m-%dT%H%M%SZ")
START_EPOCH_MS=$(($(date +%s) * 1000))
TESTSUITE_NAME="${GITHUB_OWNER:-UnknownOwner}_${GITHUB_REPO:-${PROJECT_KEY:-UnknownRepo}}_SQLValidation"
log_info "TESTSUITE_NAME: $TESTSUITE_NAME"

# --- Runtime detection ---
if [[ -f /.dockerenv ]] || grep -qE '/docker/|/lxc/' /proc/1/cgroup 2>/dev/null; then
  log_info "Running inside Docker container"
  REPORT_DIR="/home/docker/sql-report-vol"
  CTRF_REPORT_DIR="/home/docker/sql-unit-reports"
  # One UnitTH run store per project; run folders are deleted once stored.
  STORE_DIR="/home/docker/unitth-store"
elif [[ "$(uname)" == "Darwin" ]]; then
  log_info "Running on macOS"
  REPORT_DIR="$(pwd)/.reports/unitth"
  CTRF_REPORT_DIR="$(pwd)/sql-unit-reports"
  STORE_DIR=""
else
  log_info "Unknown system, defaulting to current dir"
  REPORT_DIR="$(pwd)/.reports/unitth"
  CTRF_REPORT_DIR="$(pwd)/sql-unit-reports"
  STORE_DIR=""
fi

mkdir -p "$CTRF_REPORT_DIR"
CTRF_REPORT_DIR="$(cd "$CTRF_REPORT_DIR" && pwd)"
REPORT_SUBDIR="$CTRF_REPORT_DIR/$UTC_TIMESTAMP"
if ! mkdir -p "$REPORT_SUBDIR"; then
  log_error "Failed to create directory: $REPORT_SUBDIR"
  REPORT_SUBDIR="$CTRF_REPORT_DIR"
fi
CTRF_REPORT_FILE="$REPORT_SUBDIR/TEST_${UTC_TIMESTAMP}.json"

log_info "REPORT_DIR: $REPORT_DIR"
log_info "CTRF_REPORT_DIR: $CTRF_REPORT_DIR"
log_info "CTRF_REPORT_FILE: $CTRF_REPORT_FILE"

# --- Initialize test stats ---
TOTAL_TESTS=0
FAILED_TESTS=0
PASSED_TESTS=0
SKIP_COUNT=0
TESTS_JSON="[]"

# --- Test function ---
run_test() {
  local TEST_NAME="$1"
  local SQL_QUERY="$2"
  local EXPECTED="$3"
  local OUTPUT RESULT MESSAGE STATUS
  local START_TIME_MS=$(($(date +%s) * 1000))

  if [[ "$FAKE_RUN" == true ]]; then
    RESULT="$EXPECTED"
    EXIT_CODE=0
  else
    SQL_QUERY_PROCESSED=$(echo "$SQL_QUERY" | sed "s/{{DATABASE}}/$CLONE_DATABASE/g" | sed "s/{{SCHEMA}}/$CLONE_SCHEMA_WITH_RELEASE/g")
    local STDERR_FILE
    STDERR_FILE=$(mktemp)
    OUTPUT=$(snow sql -q "$SQL_QUERY_PROCESSED" -c "$CONNECTION_NAME" --format=json 2>"$STDERR_FILE")
    CLI_EXIT_CODE=$?

    if [ $CLI_EXIT_CODE -eq 0 ]; then
      if RESULT=$(echo "$OUTPUT" | jq -r '.[0].RESULT' 2>/dev/null); then
        EXIT_CODE=0
      else
        log_error "Failed to parse JSON output: $OUTPUT"
        EXIT_CODE=1
        RESULT="JSON_PARSE_ERROR"
      fi
    else
      local STDERR_CONTENT
      STDERR_CONTENT=$(strip_ansi < "$STDERR_FILE")
      log_error "Snow CLI failed with exit code $CLI_EXIT_CODE: $STDERR_CONTENT"
      EXIT_CODE=$CLI_EXIT_CODE
      RESULT="CLI_ERROR"
      OUTPUT="$STDERR_CONTENT"
    fi
    rm -f "$STDERR_FILE"
  fi

  local END_TIME_MS=$(($(date +%s) * 1000))
  local DURATION_MS=$((END_TIME_MS - START_TIME_MS))
  if [ $DURATION_MS -lt 1 ]; then DURATION_MS=1; fi

  ((TOTAL_TESTS++))
  MESSAGE=""

  if [[ "$EXIT_CODE" -ne 0 ]]; then
    ((FAILED_TESTS++))
    STATUS="failed"
    MESSAGE="Snow CLI failed with exit code $EXIT_CODE"
  else
    RESULT_TRIMMED="$(echo "$RESULT" | xargs)"
    EXPECTED_TRIMMED="$(echo "$EXPECTED" | xargs)"

    if [[ "$RESULT_TRIMMED" != "$EXPECTED_TRIMMED" ]]; then
      ((FAILED_TESTS++))
      STATUS="failed"
      MESSAGE="Expected '$EXPECTED_TRIMMED', got '$RESULT_TRIMMED'"
      log_error "TEST FAILED: $TEST_NAME"
      log_info "   Expected: '$EXPECTED_TRIMMED'"
      log_info "   Actual:   '$RESULT_TRIMMED'"
    else
      ((PASSED_TESTS++))
      STATUS="passed"
      log_info "✅ TEST PASSED: $TEST_NAME"
    fi
  fi

  TESTS_JSON=$(echo "$TESTS_JSON" | jq \
    --arg name "$TEST_NAME" \
    --arg status "$STATUS" \
    --argjson duration "$DURATION_MS" \
    --arg message "$MESSAGE" \
    --arg suite "SQLValidation" \
    '. += [{"name": $name, "status": $status, "duration": $duration, "message": $message, "suite": $suite}]')
}

# --- Fake test logic ---
if [[ "$FAKE_RUN" == true ]]; then
  MOD=$(($(date -u +%M) % 2))
  if [[ "$MOD" -eq 0 ]]; then
    run_test "Fake Failing Test" "SELECT 'unexpected'" "expected"
  else
    run_test "Fake Passing Test" "SELECT 'expected'" "expected"
  fi
fi

# --- Run actual tests from file ---
while IFS='|' read -r description sql expected; do
  if [[ -z "$description" || "$description" =~ ^# ]]; then
    continue
  fi
  log_info "Processing: desc='$description', sql='$sql', expected='$expected'"
  run_test "$description" "$sql" "$expected"
done < "$TEST_FILE"

# --- Write CTRF JSON report ---
STOP_EPOCH_MS=$(($(date +%s) * 1000))

jq -n \
  --arg testsuite "$TESTSUITE_NAME" \
  --argjson tests "$TESTS_JSON" \
  --argjson total "$TOTAL_TESTS" \
  --argjson passed "$PASSED_TESTS" \
  --argjson failed "$FAILED_TESTS" \
  --argjson skipped "$SKIP_COUNT" \
  --argjson start "$START_EPOCH_MS" \
  --argjson stop "$STOP_EPOCH_MS" \
  --arg db "$CLONE_DATABASE" \
  --arg schema "$CLONE_SCHEMA_WITH_RELEASE" \
  '{
    reportFormat: "CTRF",
    specVersion: "0.0.1",
    results: {
      tool: { name: "sql_validation_v4" },
      summary: {
        tests: $total,
        passed: $passed,
        failed: $failed,
        skipped: $skipped,
        pending: 0,
        other: 0,
        start: $start,
        stop: $stop
      },
      tests: $tests,
      environment: {
        projectName: $testsuite,
        database: $db,
        schema: $schema
      }
    }
  }' > "$CTRF_REPORT_FILE"

log_info "CTRF_REPORT_FILE: $CTRF_REPORT_FILE"

# --- Final summary ---
log_info "📊 Summary: $TOTAL_TESTS total, $FAILED_TESTS failed, $SKIP_COUNT skipped."
if [[ "$FAILED_TESTS" -eq 0 ]]; then
  log_info "✅ All tests passed."
else
  log_error "Some tests failed. See report at $CTRF_REPORT_FILE"
fi

# --- Generate Unit History Report with unitth.jar if available ---
mkdir -p "$REPORT_DIR"

log_info "Running unitth.jar ..."
log_info "REPORT_DIR: $REPORT_DIR"
log_info "CTRF_REPORT_DIR: $CTRF_REPORT_DIR"

if [[ -z "$STORE_DIR" ]]; then
  log_info "Executing: java -Dunitth.report.dir=\"$REPORT_DIR\" -jar unitth.jar --ctrf $CTRF_REPORT_DIR/*"
  if ! (cd /usr/local/bin && java -Dunitth.report.dir="$REPORT_DIR" -jar unitth.jar --ctrf "$CTRF_REPORT_DIR"/*); then
    log_warn "unitth report generation failed (non-critical)"
  fi
  exit 0
fi

# Keep a copy in the job workspace for the SonarQube conversion step.
if ! { mkdir -p "$WORKSPACE_DIR/sql-unit-reports" && cp "$CTRF_REPORT_FILE" "$WORKSPACE_DIR/sql-unit-reports/"; }; then
  log_warn "Could not copy the CTRF report into the workspace"
fi

# Store name = project (owner_repo), file-system safe; must match migrate-ctrf-history.sh.
STORE_NAME="${TESTSUITE_NAME%_SQLValidation}"
STORE_FILE="$STORE_DIR/${STORE_NAME//[^A-Za-z0-9._-]/_}.json"
mkdir -p "$STORE_DIR"
log_info "STORE_FILE: $STORE_FILE"
UNITTH_LOG=$(mktemp)
log_info "Executing: java -Dunitth.report.dir=\"$REPORT_DIR\" -jar unitth.jar --store \"$STORE_FILE\" --store-dir \"$STORE_DIR\" --ctrf $REPORT_SUBDIR"
(cd /usr/local/bin && java -Dunitth.report.dir="$REPORT_DIR" -jar unitth.jar \
    --store "$STORE_FILE" --store-dir "$STORE_DIR" --ctrf "$REPORT_SUBDIR") 2>&1 | tee "$UNITTH_LOG" \
  || log_warn "unitth report generation failed (non-critical)"

# Delete the run folder only if UnitTH confirmed it stored this one run, and
# only if it is the folder created by this script (never the parent).
if grep -qE "found=1 .*ingest=ok" "$UNITTH_LOG" \
    && [[ "$REPORT_SUBDIR" != "$CTRF_REPORT_DIR" ]] \
    && [[ "$(basename "$REPORT_SUBDIR")" == "$UTC_TIMESTAMP" ]]; then
  rm -rf -- "$REPORT_SUBDIR" && log_info "🧹 Stored in run store, removed $REPORT_SUBDIR"
else
  log_warn "Run not confirmed in the run store, keeping $REPORT_SUBDIR"
fi
rm -f "$UNITTH_LOG"

# --- Exit always 0 — failures are tracked in CTRF report ---
exit 0
