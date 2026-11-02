#!/bin/bash
# -----------------------------------------------------------------------------
# Render and execute SQL files with Jinja-style templating
# -----------------------------------------------------------------------------
# Resolves {{ var }} placeholders from manifest.yml (templating section)
# using the target environment configuration (DEV, TE1, PRD, etc.)
#
# Modes:
#   Execute:     Renders variables and runs SQL via `snow sql` CLI
#   Render-only: Renders variables and writes output file (no execution)
#
# Usage:
#   render-sql.sh --FILE=pre_deploy.sql --TARGET=DEV --CONNECTION_NAME=myconn
#   render-sql.sh --FILE=tests.sqltest --TARGET=DEV --MANIFEST=manifest.yml --RENDER_ONLY=tests.rendered.sqltest
#
# Skips gracefully if the SQL file does not exist (exit 0).
# -----------------------------------------------------------------------------
set -Eeuo pipefail

for ARG in "$@"; do
  case $ARG in
    --FILE=*) SQL_FILE="${ARG#*=}" ;;
    --TARGET=*) TARGET="${ARG#*=}" ;;
    --CONNECTION_NAME=*) CONNECTION_NAME="${ARG#*=}" ;;
    --MANIFEST=*) MANIFEST="${ARG#*=}" ;;
    --RENDER_ONLY=*) RENDER_ONLY="${ARG#*=}" ;;
    *) echo "Unknown argument: $ARG"; exit 1 ;;
  esac
done

SQL_FILE="${SQL_FILE:?Missing --FILE}"
TARGET="${TARGET:-DEV}"
MANIFEST="${MANIFEST:-manifest.yml}"
RENDER_ONLY="${RENDER_ONLY:-}"
CONNECTION_NAME="${CONNECTION_NAME:-}"

if [[ ! -f "$SQL_FILE" ]]; then
  echo "⏭️  $SQL_FILE not found, skipping."
  exit 0
fi

if [[ ! -f "$MANIFEST" ]]; then
  echo "❌ Manifest not found: $MANIFEST"
  exit 1
fi

if [[ -n "$RENDER_ONLY" ]]; then
  python3 -c "
import yaml
with open('$MANIFEST') as f:
    m = yaml.safe_load(f)
t = m.get('templating', {})
merged = {**t.get('defaults', {}), **t.get('configurations', {}).get('$TARGET', {})}
with open('$SQL_FILE') as f:
    content = f.read()
for k, v in merged.items():
    content = content.replace('{{ ' + k + ' }}', str(v))
with open('$RENDER_ONLY', 'w') as f:
    f.write(content)
print(f'Rendered $SQL_FILE -> $RENDER_ONLY ({len(merged)} vars)')
"
  exit 0
fi

CONNECTION_NAME="${CONNECTION_NAME:?Missing --CONNECTION_NAME}"

D_ARGS=()
while IFS= read -r KV; do
  [[ -n "$KV" ]] && D_ARGS+=(-D "$KV")
done < <(python3 -c "
import yaml
with open('$MANIFEST') as f:
    m = yaml.safe_load(f)
t = m.get('templating', {})
merged = {**t.get('defaults', {}), **t.get('configurations', {}).get('$TARGET', {})}
for k, v in merged.items():
    print(f'{k}={v}')
")

echo "Running $SQL_FILE (target=$TARGET, connection=$CONNECTION_NAME)"
echo "Variables: ${D_ARGS[*]}"

snow sql -f "$SQL_FILE" -c "$CONNECTION_NAME" --enable-templating JINJA "${D_ARGS[@]}"

echo "✅ $SQL_FILE completed."
