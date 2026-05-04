#!/bin/bash

# -----------------------------------------------------------------------------
# Snowflake SQL Validation using `snow` CLI
# Output: CTRF JSON (Common Test Report Format)
# -----------------------------------------------------------------------------
# Usage:
# ./sql_validation_v4.sh \
#   --CLONE_SCHEMA=IOT_RAW_V001 \
#   --CLONE_DATABASE=DATAOPS \
#   --CONNECTION_NAME=zs28104-svc_cicd \
#   --TEST_FILE=./sqlunit/tests.sqltest
# -----------------------------------------------------------------------------

FAKE_RUN=false
RELEASE_NUM=""
set +e

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
      echo "❌ Unknown argument: $ARG"
      echo "Usage: $0 --CLONE_DATABASE=... --CLONE_SCHEMA=... --CONNECTION_NAME=... --TEST_FILE=... [--RELEASE_NUM=...] [--FAKE_RUN=...]"
      exit 1
      ;;
  esac
done

echo "FAKE_RUN is set to: $FAKE_RUN"

# --- Validation ---
if [[ -z "$CLONE_SCHEMA" || -z "$CLONE_DATABASE" || -z "$CONNECTION_NAME" || -z "$TEST_FILE" ]]; then
  echo "❌ Missing required arguments."
  exit 1
fi

if [[ ! -f "$TEST_FILE" ]]; then
  echo "❌ Test file not found: $TEST_FILE"
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
echo "TESTSUITE_NAME: $TESTSUITE_NAME"

# --- Runtime detection ---
if [[ -f /.dockerenv ]] || grep -qE '/docker/|/lxc/' /proc/1/cgroup 2>/dev/null; then
  echo "Running inside Docker container"
  REPORT_DIR="/home/docker/sql-report-vol"
  RUNTIME="container"
  CTRF_REPORT_DIR="/home/docker/sql-unit-reports"
elif [[ "$(uname)" == "Darwin" ]]; then
  echo "Running on macOS"
  RUNTIME="macos"
  REPORT_DIR="$(pwd)/sql-report-vol"
  CTRF_REPORT_DIR="$(pwd)/sql-unit-reports"
else
  echo "Unknown system, defaulting to current dir"
  RUNTIME="unknown"
  REPORT_DIR="$(pwd)/sql-report-vol"
  CTRF_REPORT_DIR="$(pwd)/sql-unit-reports"
fi

mkdir -p "$CTRF_REPORT_DIR"
CTRF_REPORT_DIR="$(cd "$CTRF_REPORT_DIR" && pwd)"
REPORT_SUBDIR="$CTRF_REPORT_DIR/$UTC_TIMESTAMP"
mkdir -p "$REPORT_SUBDIR"
if [ $? -ne 0 ]; then
  echo "❌ Failed to create directory: $REPORT_SUBDIR"
  REPORT_SUBDIR="$CTRF_REPORT_DIR"
fi
CTRF_REPORT_FILE="$REPORT_SUBDIR/TEST_${UTC_TIMESTAMP}.json"

echo "REPORT_DIR: $REPORT_DIR"
echo "CTRF_REPORT_DIR: $CTRF_REPORT_DIR"
echo "CTRF_REPORT_FILE: $CTRF_REPORT_FILE"

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
    local STDERR_FILE=$(mktemp)
    OUTPUT=$(snow sql -q "$SQL_QUERY_PROCESSED" -c "$CONNECTION_NAME" --format=json 2>"$STDERR_FILE")
    CLI_EXIT_CODE=$?

    if [ $CLI_EXIT_CODE -eq 0 ]; then
      RESULT=$(echo "$OUTPUT" | jq -r '.[0].RESULT' 2>/dev/null)
      if [ $? -ne 0 ]; then
        echo "❌ Failed to parse JSON output: $OUTPUT"
        EXIT_CODE=1
        RESULT="JSON_PARSE_ERROR"
      else
        EXIT_CODE=0
      fi
    else
      local STDERR_CONTENT=$(cat "$STDERR_FILE" | strip_ansi)
      echo "❌ Snow CLI failed with exit code $CLI_EXIT_CODE: $STDERR_CONTENT"
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
      echo "❌ TEST FAILED: $TEST_NAME"
      echo "   Expected: '$EXPECTED_TRIMMED'"
      echo "   Actual:   '$RESULT_TRIMMED'"
    else
      ((PASSED_TESTS++))
      STATUS="passed"
      echo "✅ TEST PASSED: $TEST_NAME"
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
    ((SKIP_COUNT++))
    ((TOTAL_TESTS++))
    trimmed_desc="$(echo "${description:-Unnamed Skipped Test}" | xargs)"
    TESTS_JSON=$(echo "$TESTS_JSON" | jq \
      --arg name "$trimmed_desc" \
      --arg status "skipped" \
      --arg suite "SQLValidation" \
      '. += [{"name": $name, "status": $status, "duration": 0, "message": "", "suite": $suite}]')
    continue
  fi
  echo "Processing: desc='$description', sql='$sql', expected='$expected'"
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

echo "CTRF_REPORT_FILE: $CTRF_REPORT_FILE"

# --- Final summary ---
echo -e "\n📊 Summary: $TOTAL_TESTS total, $FAILED_TESTS failed, $SKIP_COUNT skipped."
if [[ "$FAILED_TESTS" -eq 0 ]]; then
  echo "✅ All tests passed."
else
  echo "❌ Some tests failed. See report at $CTRF_REPORT_FILE"
fi

# --- Generate Unit History Report with unitth.jar if available ---
mkdir -p "$REPORT_DIR"

echo "Running unitth.jar ..."
echo "REPORT_DIR: $REPORT_DIR"
echo "CTRF_REPORT_DIR: $CTRF_REPORT_DIR"
echo "Executing: java -Dunitth.report.dir=\"$REPORT_DIR\" -jar unitth.jar --ctrf $CTRF_REPORT_DIR/*"

cd /usr/local/bin && java -Dunitth.report.dir="$REPORT_DIR" -jar unitth.jar --ctrf "$CTRF_REPORT_DIR"/* || echo "unitth report generation failed (non-critical)"

# --- Exit always 0 — failures are tracked in CTRF report ---
exit 0
