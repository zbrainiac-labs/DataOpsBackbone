#!/bin/bash
# -----------------------------------------------------------------------------
# Clone a Snowflake schema and create a DCM project in the clone.
# Used for regression testing: deploy + test against an isolated copy.
# -----------------------------------------------------------------------------
# Usage:
#   snowflake-clone-schema_v3.sh \
#     --SOURCE_DATABASE=DATAOPS \
#     --SOURCE_SCHEMA=IOT_RAW_V001 \
#     --RELEASE_NUM=42 \
#     --PROJECT_KEY=MOTHER_OF_ALL_PROJECTS \
#     --CONNECTION_NAME=zs28104-svc_cicd
#
# Result: DATAOPS.IOT_RAW_V001_42 (clone) with DCM project created
# -----------------------------------------------------------------------------
set +e
set -u

for ARG in "$@"; do
  case $ARG in
    --SOURCE_DATABASE=*) SOURCE_DATABASE="${ARG#*=}" ;;
    --SOURCE_SCHEMA=*) SOURCE_SCHEMA="${ARG#*=}" ;;
    --RELEASE_NUM=*) RELEASE_NUM="${ARG#*=}" ;;
    --PROJECT_KEY=*) PROJECT_KEY="${ARG#*=}" ;;
    --CONNECTION_NAME=*) CONNECTION_NAME="${ARG#*=}" ;;
    *) echo "Unknown argument: $ARG"; exit 1 ;;
  esac
done

if [[ -z "${SOURCE_DATABASE:-}" || -z "${SOURCE_SCHEMA:-}" || -z "${RELEASE_NUM:-}" || -z "${CONNECTION_NAME:-}" ]]; then
  echo "Missing required arguments."
  echo "Required: --SOURCE_DATABASE --SOURCE_SCHEMA --RELEASE_NUM --CONNECTION_NAME [--PROJECT_KEY]"
  exit 1
fi

CLONE_SCHEMA="${SOURCE_SCHEMA}_${RELEASE_NUM}"

echo "Cloning: ${SOURCE_DATABASE}.${SOURCE_SCHEMA} -> ${SOURCE_DATABASE}.${CLONE_SCHEMA}"

snow sql -c "$CONNECTION_NAME" -q "
CREATE OR REPLACE SCHEMA ${SOURCE_DATABASE}.${CLONE_SCHEMA} CLONE ${SOURCE_DATABASE}.${SOURCE_SCHEMA};
"
if [ $? -ne 0 ]; then
  echo "Clone failed"
  exit 1
fi
echo "Clone created: ${SOURCE_DATABASE}.${CLONE_SCHEMA}"

if [[ -n "${PROJECT_KEY:-}" ]]; then
  echo "Creating DCM project: ${SOURCE_DATABASE}.${CLONE_SCHEMA}.${PROJECT_KEY}"
  snow sql -c "$CONNECTION_NAME" -q "
CREATE DCM PROJECT IF NOT EXISTS ${SOURCE_DATABASE}.${CLONE_SCHEMA}.${PROJECT_KEY};
"
  if [ $? -ne 0 ]; then
    echo "DCM project creation failed (non-critical)"
  fi
fi

echo "Done: ${SOURCE_DATABASE}.${CLONE_SCHEMA}"
