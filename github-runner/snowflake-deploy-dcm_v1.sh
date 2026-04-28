#!/bin/bash

# -----------------------------------------------------------------------------
# DCM Deploy Script - replaces snowflake-deploy-structure_v2.sh
# Runs: analyze -> plan -> deploy using Snowflake DCM
# -----------------------------------------------------------------------------
# Usage:
# ./snowflake-deploy-dcm_v1.sh \
#   --PROJECT_IDENTIFIER=DATAOPS.IOT_RAW_V001.MOTHER_OF_ALL_PROJECTS \
#   --CONNECTION_NAME=zs28104-svc_cicd \
#   --TARGET=DEV \
#   --ALIAS=v42 \
#   --PROJECT_DIR=/path/to/project
# -----------------------------------------------------------------------------

set -e

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
      echo "Unknown argument: $ARG"
      exit 1
      ;;
  esac
done

if [[ -z "$PROJECT_IDENTIFIER" || -z "$CONNECTION_NAME" ]]; then
  echo "Missing required arguments."
  echo "Required: --PROJECT_IDENTIFIER --CONNECTION_NAME [--TARGET] [--ALIAS] [--PROJECT_DIR]"
  exit 1
fi

TARGET="${TARGET:-DEV}"
ALIAS="${ALIAS:-release-$(date -u +%Y%m%dT%H%M%S)}"

if [[ -n "$PROJECT_DIR" ]]; then
  cd "$PROJECT_DIR"
fi

echo "DCM Deployment"
echo "=================================================="
echo "  Project:    $PROJECT_IDENTIFIER"
echo "  Connection: $CONNECTION_NAME"
echo "  Target:     $TARGET"
echo "  Alias:      $ALIAS"
echo "  Directory:  $(pwd)"
echo "=================================================="

echo ""
if [[ -f "pre_deploy.sql" ]]; then
  echo "Step 0: Running pre_deploy.sql..."
  snow sql -f pre_deploy.sql -c "$CONNECTION_NAME"
  echo "Pre-deploy completed."
  echo ""
fi

echo "Step 1: Running DCM analyze..."
snow dcm raw-analyze "$PROJECT_IDENTIFIER" -c "$CONNECTION_NAME" --target "$TARGET"
echo "Analyze completed."

echo ""
echo "Step 2: Running DCM plan..."
snow dcm plan "$PROJECT_IDENTIFIER" -c "$CONNECTION_NAME" --target "$TARGET" --save-output
echo "Plan completed."

if [[ -f "out/plan/plan_result.json" ]]; then
  echo ""
  echo "Plan summary:"
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
" || echo "  Could not parse plan output."
fi

echo ""
echo "Step 3: Running DCM deploy..."
snow dcm deploy "$PROJECT_IDENTIFIER" -c "$CONNECTION_NAME" --target "$TARGET" --alias "$ALIAS"
echo "Deploy completed."

if [[ -f "post_deploy.sql" ]]; then
  echo ""
  echo "Step 4: Running post_deploy.sql..."
  snow sql -f post_deploy.sql -c "$CONNECTION_NAME"
  echo "Post-deploy completed."
fi

echo ""
echo "DCM Deployment finished successfully."
echo "=================================================="
