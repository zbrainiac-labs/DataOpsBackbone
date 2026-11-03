#!/bin/bash

# -----------------------------------------------------------------------------
# DCM Deploy Script - replaces snowflake-deploy-structure_v2.sh
# Runs: analyze -> plan -> deploy using Snowflake DCM
# -----------------------------------------------------------------------------
# Usage:
# ./snowflake-deploy-dcm.sh \
#   --PROJECT_IDENTIFIER=DATAOPS.IOT_RAW_V001.MOTHER_OF_ALL_PROJECTS \
#   --CONNECTION_NAME=zs28104-svc_cicd \
#   --TARGET=DEV \
#   --ALIAS=v42 \
#   --PROJECT_DIR=/path/to/project
# -----------------------------------------------------------------------------

set -Eeuo pipefail
LIB="$(dirname "${BASH_SOURCE[0]}")/lib.sh"; [[ -f "$LIB" ]] || LIB=/usr/local/bin/lib.sh
# shellcheck source=/dev/null
source "$LIB"

for ARG in "$@"; do
  case $ARG in
    --PROJECT_IDENTIFIER=*)
      PROJECT_IDENTIFIER="${ARG#*=}" ;;
    --CONNECTION_NAME=*)
      CONNECTION_NAME="${ARG#*=}" ;;
    --TARGET=*)
      TARGET="${ARG#*=}" ;;
    --ALIAS=*)
      ALIAS="${ARG#*=}" ;;
    --PROJECT_DIR=*)
      PROJECT_DIR="${ARG#*=}" ;;
    *)
      log_error "Unknown argument: $ARG"
      exit 1
      ;;
  esac
done

if [[ -z "$PROJECT_IDENTIFIER" || -z "$CONNECTION_NAME" ]]; then
  log_error "Missing required arguments."
  log_info "Required: --PROJECT_IDENTIFIER --CONNECTION_NAME [--TARGET] [--ALIAS] [--PROJECT_DIR]"
  exit 1
fi

TARGET="${TARGET:-DEV}"
ALIAS="${ALIAS:-release-$(date -u +%Y%m%dT%H%M%S)}"

if [[ -n "$PROJECT_DIR" ]]; then
  cd "$PROJECT_DIR"
fi

log_info "DCM Deployment"
log_info "=================================================="
log_info "  Project:    $PROJECT_IDENTIFIER"
log_info "  Connection: $CONNECTION_NAME"
log_info "  Target:     $TARGET"
log_info "  Alias:      $ALIAS"
log_info "  Directory:  $(pwd)"
log_info "=================================================="

if [[ -f "pre_deploy.sql" ]]; then
  log_info "Step 0: Skipping pre_deploy.sql (already executed by pipeline)"
fi

log_info "Step 1: Running DCM analyze..."
snow dcm raw-analyze "$PROJECT_IDENTIFIER" -c "$CONNECTION_NAME" --target "$TARGET"
log_info "Analyze completed."

log_info "Step 2: Running DCM plan..."
snow dcm plan "$PROJECT_IDENTIFIER" -c "$CONNECTION_NAME" --target "$TARGET" --save-output
log_info "Plan completed."

if [[ -f "out/plan/plan_result.json" ]]; then
  log_info "Plan summary:"
  python3 -c "
import json, sys
data = json.load(open('out/plan/plan_result.json'))
status = data.get('status', 'UNKNOWN')
print(f'  Status: {status}')
ops = data.get('operations', [])
creates = [o for o in ops if o.get('operation') == 'CREATE']
alters = [o for o in ops if o.get('operation') == 'ALTER']
drops = [o for o in ops if o.get('operation') == 'DROP']
noop = [o for o in ops if o.get('operation') == 'NO_OPERATION']
print(f'  CREATE: {len(creates)}  ALTER: {len(alters)}  DROP: {len(drops)}  NO_CHANGE: {len(noop)}')
if drops:
    print('  WARNING: The following objects will be DROPPED:')
    for d in drops:
        print(f'    - {d.get(\"object_name\", \"unknown\")}')
if status == 'PLAN_FAILED':
    print('  Plan FAILED. Check errors above.')
    sys.exit(1)
" || log_warn "Could not parse plan output."
fi

log_info "Step 3: Running DCM deploy..."
snow dcm deploy "$PROJECT_IDENTIFIER" -c "$CONNECTION_NAME" --target "$TARGET" --alias "$ALIAS"
log_info "Deploy completed."

if [[ -f "post_deploy.sql" ]]; then
  log_info "Step 4: Skipping post_deploy.sql (executed by pipeline after DCM deploy)"
fi

log_info "DCM Deployment finished successfully."
log_info "=================================================="
