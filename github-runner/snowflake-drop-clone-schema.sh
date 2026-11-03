#!/bin/bash
# -----------------------------------------------------------------------------
# Drop a cloned schema (cleanup after regression test)
# -----------------------------------------------------------------------------
# Usage:
#   snowflake-drop-clone-schema.sh \
#     --SOURCE_DATABASE=DATAOPS \
#     --SOURCE_SCHEMA=IOT_RAW_V001 \
#     --RELEASE_NUM=42 \
#     --CONNECTION_NAME=zs28104-svc_cicd
#
# Drops: DATAOPS.IOT_RAW_V001_42
# -----------------------------------------------------------------------------
set +e
LIB="$(dirname "${BASH_SOURCE[0]}")/lib.sh"; [[ -f "$LIB" ]] || LIB=/usr/local/bin/lib.sh
# shellcheck source=/dev/null
source "$LIB"
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
  log_error "Missing required arguments."
  log_info "Required: --SOURCE_DATABASE --SOURCE_SCHEMA --RELEASE_NUM --CONNECTION_NAME"
  exit 1
fi

CLONE_SCHEMA="${SOURCE_SCHEMA}_${RELEASE_NUM}"

log_info "Dropping clone: ${SOURCE_DATABASE}.${CLONE_SCHEMA}"

if snow sql -c "$CONNECTION_NAME" -q "
DROP SCHEMA IF EXISTS ${SOURCE_DATABASE}.${CLONE_SCHEMA};
"; then
  log_info "Dropped: ${SOURCE_DATABASE}.${CLONE_SCHEMA}"
else
  log_warn "Drop failed (non-critical)"
fi
