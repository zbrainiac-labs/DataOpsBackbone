#!/bin/bash

# -----------------------------------------------------------------------------
# Snowflake SQL Validation using `snow` CLI
# -----------------------------------------------------------------------------
# Usage:
# ./sql_validation_v2.sh \
#   --CLONE_SCHEMA=IOT_CLONE \
#   --CLONE_DATABASE=DataOps \
#   --RELEASE_NUM=42 \
#   --CONNECTION_NAME=sfseeurope-svc_cicd_user
#
# cd /usr/local/bin && ./sql_validation_v4.sh --CLONE_SCHEMA=IOT_CLONE --CLONE_DATABASE=DataOps --RELEASE_NUM=42 --CONNECTION_NAME=sfseeurope-svc_cicd_user --TEST_FILE=tests.sqltest --JUNIT_REPORT_DIR=/tmp/sql-unit-report
# ./sql_validation_v4.sh --CLONE_SCHEMA=IOT_CLONE --CLONE_DATABASE=DataOps --RELEASE_NUM=42 --CONNECTION_NAME=sfseeurope-svc_cicd_user --TEST_FILE=tests.sqltest --FAKE_RUN=false
# ./sql_validation_v4.sh --CLONE_SCHEMA=IOT_CLONE --CLONE_DATABASE=DataOps --RELEASE_NUM=42 --CONNECTION_NAME=sfseeurope-svc_cicd_user --TEST_FILE=tests.sqltest --FAKE_RUN=false
# -----------------------------------------------------------------------------

FAKE_RUN=false  # Default value
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
      echo "Usage: $0 --CLONE_DATABASE=... --CLONE_SCHEMA=... --RELEASE_NUM=... --CONNECTION_NAME=... --TEST_FILE=... --FAKE_RUN=..."
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
TESTSUITE_NAME="${GITHUB_OWNER:-UnknownOwner}_${GITHUB_REPO:-${PROJECT_KEY:-UnknownRepo}}_SQLValidation"
echo "TESTSUITE_NAME: $TESTSUITE_NAME"

# --- Runtime detection ---
if [[ -f /.dockerenv ]] || grep -qE '/docker/|/lxc/' /proc/1/cgroup 2>/dev/null; then
  echo "Running inside Docker container"
  REPORT_DIR="/home/docker/sql-report-vol"
  RUNTIME="container"
  JUNIT_REPORT_DIR="/home/docker/sql-unit-reports"
elif [[ "$(uname)" == "Darwin" ]]; then
 echo "Running on macOS"
  RUNTIME="macos"
  REPORT_DIR="$(pwd)/sql-report-vol"
  JUNIT_REPORT_DIR="$(pwd)/sql-unit-reports"
else
  echo "Unknown system, defaulting to current dir"
  RUNTIME="unknown"
  REPORT_DIR="$(pwd)/sql-report-vol"
  JUNIT_REPORT_DIR="$(pwd)/sql-unit-reports"
fi

# Create directory if it doesn't exist, then get absolute path
mkdir -p "$JUNIT_REPORT_DIR"
JUNIT_REPORT_DIR="$(cd "$JUNIT_REPORT_DIR" && pwd)"
REPORT_SUBDIR="$JUNIT_REPORT_DIR/$UTC_TIMESTAMP"
echo "Creating directory: $REPORT_SUBDIR"
mkdir -p "$REPORT_SUBDIR"
if [ $? -ne 0 ]; then
  echo "❌ Failed to create directory: $REPORT_SUBDIR"
  echo "❌ Falling back to JUNIT_REPORT_DIR: $JUNIT_REPORT_DIR"
  REPORT_SUBDIR="$JUNIT_REPORT_DIR"
fi
JUNIT_REPORT_FILE="$REPORT_SUBDIR/TEST_${UTC_TIMESTAMP}.xml"

echo "REPORT_DIR: $REPORT_DIR"
echo "JUNIT_REPORT_DIR: $JUNIT_REPORT_DIR"
echo "JUNIT_REPORT_FILE: $JUNIT_REPORT_FILE"

# --- Initialize test stats ---
TOTAL_TESTS=0
FAILED_TESTS=0
SKIP_COUNT=0
TOTAL_TIME=0

# --- Start writing JUnit XML ---
{
  echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" > "$JUNIT_REPORT_FILE"
  echo "<testsuite name=\"${TESTSUITE_NAME}\" tests=\"0\" failures=\"0\" skipped=\"0\" time=\"0.000\">"
} > "$JUNIT_REPORT_FILE"

# --- Test function ---
run_test() {
  local TEST_NAME="$1"
  local SQL_QUERY="$2"
  local EXPECTED="$3"
  local OUTPUT RESULT
  local START_TIME=$(date +%s)

  if [[ "$FAKE_RUN" == true ]]; then
    RESULT="$EXPECTED"   # simulate perfect match
    EXIT_CODE=0
  else
    SQL_QUERY_PROCESSED=$(echo "$SQL_QUERY" | sed "s/{{DATABASE}}/$CLONE_DATABASE/g" | sed "s/{{SCHEMA}}/$CLONE_SCHEMA_WITH_RELEASE/g")
    # use snow cli to execute command
    # Execute snow CLI with error handling
    OUTPUT=$(snow sql -q "$SQL_QUERY_PROCESSED" -c "$CONNECTION_NAME" --format=json 2>&1)
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
      echo "❌ Snow CLI failed with exit code $CLI_EXIT_CODE: $OUTPUT"
      EXIT_CODE=$CLI_EXIT_CODE
      RESULT="CLI_ERROR"
    fi
  fi

  local END_TIME=$(date +%s)
  local DURATION=$(awk "BEGIN { d = $END_TIME - $START_TIME; if (d < 0.0001) d = 0.001; printf \"%.3f\", d }") || DURATION="0.001"
  TOTAL_TIME=$(awk -v total="$TOTAL_TIME" -v add="$DURATION" 'BEGIN { printf "%.3f", total + add }')

  ((TOTAL_TESTS++))

  if [[ "$EXIT_CODE" -ne 0 ]]; then
    ((FAILED_TESTS++))
    {
      echo "  <testcase name=\"$TEST_NAME\" classname=\"SQLValidation\" time=\"$DURATION\">"
      echo "    <failure message=\"snow CLI failed\">$OUTPUT</failure>"
      echo "  </testcase>"
    } >> "$JUNIT_REPORT_FILE"
    return
  fi

  # Trim both actual and expected
  RESULT_TRIMMED="$(echo "$RESULT" | xargs)"
  EXPECTED_TRIMMED="$(echo "$EXPECTED" | xargs)"

  if [[ "$RESULT_TRIMMED" != "$EXPECTED_TRIMMED" ]]; then
  ((FAILED_TESTS++))
    echo "❌ TEST FAILED: $TEST_NAME"
    echo "   Expected: '$EXPECTED_TRIMMED'"
    echo "   Actual:   '$RESULT_TRIMMED'"
    echo "   SQL: $SQL_QUERY"
    {
      echo "  <testcase name=\"$TEST_NAME\" classname=\"SQLValidation\" time=\"$DURATION\">"
      echo "    <failure message=\"Expected '$EXPECTED_TRIMMED', got '$RESULT_TRIMMED'\">"
      echo "SQL: $SQL_QUERY"
      echo "Expected (raw): $EXPECTED"
      echo "Actual (raw): $RESULT"
      echo "Expected (trimmed): $EXPECTED_TRIMMED"
      echo "Actual (trimmed): $RESULT_TRIMMED"
      echo "    </failure>"
      echo "  </testcase>"
    } >> "$JUNIT_REPORT_FILE"

  else
    echo "✅ TEST PASSED: $TEST_NAME"
    echo "  <testcase name=\"$TEST_NAME\" classname=\"SQLValidation\" time=\"$DURATION\"/>" >> "$JUNIT_REPORT_FILE"
  fi
}

# --- Fake test logic ---
if [[ "$FAKE_RUN" == true ]]; then
  MOD=$(($(date -u +%M) % 2))
  if [[ "$MOD" -eq 0 ]]; then
    run_test "🧪 Fake Failing Test" "SELECT 'unexpected'" "expected"
  else
    run_test "🧪 Fake Passing Test" "SELECT 'expected'" "expected"
  fi
fi

# --- Run actual tests from file ---
while IFS='|' read -r description sql expected; do
  if [[ -z "$description" || "$description" =~ ^# ]]; then
    ((SKIP_COUNT++))
    trimmed_desc="$(echo "${description:-Unnamed Skipped Test}" | xargs)"
    echo "  <testcase name=\"$trimmed_desc\" classname=\"SQLValidation\" time=\"0\"><skipped message=\"Commented or empty\"/></testcase>" >> "$JUNIT_REPORT_FILE"
    continue
  fi
  echo "Processing: desc='$description', sql='$sql', expected='$expected'"
  run_test "$description" "$sql" "$expected"
done < "$TEST_FILE"

# --- Close XML ---
echo "</testsuite>" >> "$JUNIT_REPORT_FILE"

# --- Patch suite summary ---
echo "JUNIT_REPORT_FILE: $JUNIT_REPORT_FILE"

TOTAL_TIME_FMT=$(printf "%.3f" "$TOTAL_TIME")

if [[ "$RUNTIME" == "macos" ]]; then

  sed -i '' \
      -e "s/time=\"0.000\"/time=\"$(awk -v t="$TOTAL_TIME" 'BEGIN {printf "%.3f", t}')\"/" \
      "$JUNIT_REPORT_FILE"

  sed -i '' \
    -e "s/tests=\"0\"/tests=\"$TOTAL_TESTS\"/" \
    -e "s/failures=\"0\"/failures=\"$FAILED_TESTS\"/" \
    -e "s/skipped=\"0\"/skipped=\"$SKIP_COUNT\"/" \
    -e "s/time=\"0.000\"/time=\"$TOTAL_TIME_FMT\"/" \
    "$JUNIT_REPORT_FILE"
else

  sed -i  \
      -e "s/time=\"0.000\"/time=\"$(awk -v t="$TOTAL_TIME" 'BEGIN {printf "%.3f", t}')\"/" \
      "$JUNIT_REPORT_FILE"

  sed -i \
    -e "s/tests=\"0\"/tests=\"$TOTAL_TESTS\"/" \
    -e "s/failures=\"0\"/failures=\"$FAILED_TESTS\"/" \
    -e "s/skipped=\"0\"/skipped=\"$SKIP_COUNT\"/" \
    -e "s/time=\"0.000\"/time=\"$TOTAL_TIME_FMT\"/" \
    "$JUNIT_REPORT_FILE"
fi

# --- Final summary ---
echo -e "\n📊 Summary: $TOTAL_TESTS total, $FAILED_TESTS failed, $SKIP_COUNT skipped."
if [[ "$FAILED_TESTS" -eq 0 ]]; then
  echo "✅ All tests passed."
else
  echo "❌ Some tests failed. See report at $JUNIT_REPORT_FILE"
fi

# --- Generate Unit History Report with  unitth.jar if available ---
mkdir -p "$REPORT_DIR"

echo "Running unitth.jar ..."
echo "REPORT_DIR: $REPORT_DIR"
echo "JUNIT_REPORT_DIR: $JUNIT_REPORT_DIR"
echo "Executing: java -Dunitth.report.dir=\"$REPORT_DIR\" -Dunitth.html.report.path=\"$REPORT_DIR\" -jar unitth.jar $JUNIT_REPORT_DIR/*"

cd /usr/local/bin && java -Dunitth.report.dir="$REPORT_DIR" -jar unitth.jar "$JUNIT_REPORT_DIR"/* || echo "unitth report generation failed (non-critical)"

# --- Exit always 0 — failures are tracked in JUnit report ---
exit 0
