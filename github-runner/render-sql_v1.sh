#!/bin/bash
set -e

for ARG in "$@"; do
  case $ARG in
    --FILE=*) SQL_FILE="${ARG#*=}" ;;
    --TARGET=*) TARGET="${ARG#*=}" ;;
    --CONNECTION_NAME=*) CONNECTION_NAME="${ARG#*=}" ;;
    --MANIFEST=*) MANIFEST="${ARG#*=}" ;;
    *) echo "Unknown argument: $ARG"; exit 1 ;;
  esac
done

SQL_FILE="${SQL_FILE:?Missing --FILE}"
CONNECTION_NAME="${CONNECTION_NAME:?Missing --CONNECTION_NAME}"
TARGET="${TARGET:-DEV}"
MANIFEST="${MANIFEST:-manifest.yml}"

if [[ ! -f "$SQL_FILE" ]]; then
  echo "⏭️  $SQL_FILE not found, skipping."
  exit 0
fi

if [[ ! -f "$MANIFEST" ]]; then
  echo "❌ Manifest not found: $MANIFEST"
  exit 1
fi

D_FLAGS=$(python3 -c "
import yaml, sys

with open('$MANIFEST') as f:
    m = yaml.safe_load(f)

t = m.get('templating', {})
defaults = t.get('defaults', {})
config = t.get('configurations', {}).get('$TARGET', {})

merged = {**defaults, **config}

for k, v in merged.items():
    print(f'-D {k}={v}')
")

echo "Running $SQL_FILE (target=$TARGET, connection=$CONNECTION_NAME)"
echo "Variables: $(echo $D_FLAGS | tr '\n' ' ')"

eval snow sql -f "$SQL_FILE" -c "$CONNECTION_NAME" $D_FLAGS

echo "✅ $SQL_FILE completed."
