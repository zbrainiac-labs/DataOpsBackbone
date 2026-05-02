#!/bin/bash
set +e

PROJECT_DIR="${1:-.}"
OUTPUT_FILE="${2:-sqlfluff_issues.json}"

echo "Running SQLFluff on $PROJECT_DIR..."

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
  echo "No SQLFluff issues found."
  rm -f "$TMPJSON"
  exit 0
fi

CONVERTER="/usr/local/bin/sqlfluff_to_sonar.py"
if [[ ! -f "$CONVERTER" ]]; then
  CONVERTER="$(dirname "$0")/sqlfluff_to_sonar.py"
fi

python3 "$CONVERTER" "$TMPJSON" "$OUTPUT_FILE"
rm -f "$TMPJSON"
