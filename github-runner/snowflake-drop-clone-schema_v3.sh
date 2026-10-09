#!/bin/bash
# -----------------------------------------------------------------------------
# Drop a cloned schema (cleanup after regression test)
# -----------------------------------------------------------------------------
# Usage:
#   snowflake-drop-clone-schema_v3.sh \
#     --SOURCE_DATABASE=DATAOPS \
#     --SOURCE_SCHEMA=IOT_RAW_V001 \
#     --RELEASE_NUM=42 \
#     --CONNECTION_NAME=zs28104-svc_cicd
#
# Drops: DATAOPS.IOT_RAW_V001_42
# -----------------------------------------------------------------------------
set +e
set -u

for ARG in "$@"; do
  case $ARG in
    --SOURCE_DATABASE=*) SOURCE_DATABASE="${ARG#*=}" ;;
    --SOURCE_SCHEMA=*) SOURCE_SCHEMA="${ARG#*=}" ;;
    --RELEASE_NUM=*) RELEASE_NUM="${ARG#*=}" ;;
    --CONNECTION_NAME=*) CONNECTION_NAME="${ARG#*=}" ;;
    *) echo "Unknown argument: $ARG"; exit 1 ;;
  esac
done

if [[ -z "${SOURCE_DATABASE:-}" || -z "${SOURCE_SCHEMA:-}" || -z "${RELEASE_NUM:-}" || -z "${CONNECTION_NAME:-}" ]]; then
  echo "Missing required arguments."
  echo "Required: --SOURCE_DATABASE --SOURCE_SCHEMA --RELEASE_NUM --CONNECTION_NAME"
  exit 1
fi

CLONE_SCHEMA="${SOURCE_SCHEMA}_${RELEASE_NUM}"

echo "Dropping clone: ${SOURCE_DATABASE}.${CLONE_SCHEMA}"

if snow sql -c "$CONNECTION_NAME" -q "
DROP SCHEMA IF EXISTS ${SOURCE_DATABASE}.${CLONE_SCHEMA};
"; then
  echo "Dropped: ${SOURCE_DATABASE}.${CLONE_SCHEMA}"
else
  echo "Drop failed (non-critical)"
fi
