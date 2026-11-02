#!/bin/bash
# -----------------------------------------------------------------------------
# Prepare an isolated per-build schema for regression testing.
#
# Creates an EMPTY schema <SOURCE_SCHEMA>_<RELEASE_NUM> plus a DCM project in it,
# copies the project to a temp work dir and points its manifest at the new schema
# (DEFINE WAREHOUSE is stripped -- warehouses are account-level, not per build).
# DCM then deploys the full definition into the empty schema.
#
# Usage:
#   snowflake-clone-schema.sh --SOURCE_DATABASE=DB --SOURCE_SCHEMA=SCH --RELEASE_NUM=42 \
#     --DCM_PROJECT_IDENTIFIER=DB.SCH.PROJECT --TARGET=DEV --CONNECTION_NAME=conn [--PROJECT_DIR=.]
#
# Outputs (GitHub Actions): clone_schema, work_dir to $GITHUB_OUTPUT and
# CLONE_SCHEMA, WORK_DIR, DCM_PROJECT_IDENTIFIER to $GITHUB_ENV.
# -----------------------------------------------------------------------------
set -Eeuo pipefail
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PROJECT_DIR="."
for ARG in "$@"; do
  case $ARG in
    --SOURCE_DATABASE=*) SOURCE_DATABASE="${ARG#*=}" ;;
    --SOURCE_SCHEMA=*) SOURCE_SCHEMA="${ARG#*=}" ;;
    --RELEASE_NUM=*) RELEASE_NUM="${ARG#*=}" ;;
    --DCM_PROJECT_IDENTIFIER=*) DCM_PROJECT_IDENTIFIER="${ARG#*=}" ;;
    --TARGET=*) TARGET="${ARG#*=}" ;;
    --CONNECTION_NAME=*) CONNECTION_NAME="${ARG#*=}" ;;
    --PROJECT_DIR=*) PROJECT_DIR="${ARG#*=}" ;;
    *) echo "Unknown argument: $ARG"; exit 1 ;;
  esac
done
: "${SOURCE_DATABASE:?--SOURCE_DATABASE required}" "${SOURCE_SCHEMA:?--SOURCE_SCHEMA required}"
: "${RELEASE_NUM:?--RELEASE_NUM required}" "${DCM_PROJECT_IDENTIFIER:?--DCM_PROJECT_IDENTIFIER required}"
: "${TARGET:?--TARGET required}" "${CONNECTION_NAME:?--CONNECTION_NAME required}"

PROJECT_NAME="${DCM_PROJECT_IDENTIFIER##*.}"
CLONE_SCHEMA="${SOURCE_SCHEMA}_${RELEASE_NUM}"
CLONE_PROJECT="${SOURCE_DATABASE}.${CLONE_SCHEMA}.${PROJECT_NAME}"

echo "Preparing build schema ${SOURCE_DATABASE}.${CLONE_SCHEMA}"
snow sql -c "$CONNECTION_NAME" -q "CREATE OR REPLACE SCHEMA IDENTIFIER('${SOURCE_DATABASE}.${CLONE_SCHEMA}');"
retry snow sql -c "$CONNECTION_NAME" -q "CREATE DCM PROJECT IF NOT EXISTS IDENTIFIER('${CLONE_PROJECT}');"

WORK_DIR=$(mktemp -d)
cp -r "$PROJECT_DIR/." "$WORK_DIR/"

TARGET="$TARGET" SCHEMA="$CLONE_SCHEMA" PROJECT="$CLONE_PROJECT" MANIFEST="$WORK_DIR/manifest.yml" python3 - <<'PY'
import os, yaml
path, target, schema = os.environ["MANIFEST"], os.environ["TARGET"], os.environ["SCHEMA"]
with open(path) as f:
    m = yaml.safe_load(f)
m["targets"][target]["project_name"] = os.environ["PROJECT"]
t = m.setdefault("templating", {})
t.setdefault("defaults", {})["schema"] = schema
cfg = t.get("configurations", {}).get(target)
if cfg:
    cfg["schema"] = schema
with open(path, "w") as f:
    yaml.dump(m, f, default_flow_style=False)
PY

INFRA="$WORK_DIR/sources/definitions/infrastructure.sql"
[[ -f "$INFRA" ]] && sed -i '/^DEFINE WAREHOUSE/,/;$/d' "$INFRA"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  { echo "clone_schema=${CLONE_SCHEMA}"; echo "work_dir=${WORK_DIR}"; } >> "$GITHUB_OUTPUT"
  { echo "CLONE_SCHEMA=${CLONE_SCHEMA}"; echo "WORK_DIR=${WORK_DIR}"
    echo "DCM_PROJECT_IDENTIFIER=${CLONE_PROJECT}"; } >> "$GITHUB_ENV"
fi
echo "Build schema ready: ${SOURCE_DATABASE}.${CLONE_SCHEMA} (work dir: ${WORK_DIR})"
