#!/bin/bash

# -----------------------------------------------------------------------------
# DataOps Pipeline Master Script (DCM Edition)
# Executes: Dependencies -> DCM Deploy -> SonarQube -> SQL Validation
# -----------------------------------------------------------------------------

set -e

export SOURCE_DATABASE="${SOURCE_DATABASE:-DATAOPS}"
export SOURCE_SCHEMA="${SOURCE_SCHEMA:-IOT_RAW_V001}"
export PROJECT_KEY="${PROJECT_KEY:-mother-of-all-Projects}"
export CONNECTION_NAME="${CONNECTION_NAME:-zs28104-svc_cicd}"
export RELEASE_NUM="${RELEASE_NUM:-v001}"
export TEST_FILE="${TEST_FILE:-./github-runner/tests.sqltest}"
export FAKE_RUN="${FAKE_RUN:-false}"
export DCM_PROJECT_IDENTIFIER="${DCM_PROJECT_IDENTIFIER:-DATAOPS.IOT_RAW_V001.MOTHER_OF_ALL_PROJECTS}"
export DCM_TARGET="${DCM_TARGET:-DEV}"

if [[ -f /.dockerenv ]] || grep -qE '/docker/|/lxc/' /proc/1/cgroup 2>/dev/null; then
  echo "Running inside Docker container"
  export BASE_WORKSPACE="${BASE_WORKSPACE:-/home/docker/actions-runner/_work}"
  export OUTPUT_DIR="${OUTPUT_DIR:-/home/docker/actions-runner/_work/${PROJECT_KEY}/${PROJECT_KEY}}"
elif [[ "$(uname)" == "Darwin" ]]; then
  echo "Running on macOS"
  export BASE_WORKSPACE="${BASE_WORKSPACE:-/Users/mdaeppen/workspace}"
  export OUTPUT_DIR="${OUTPUT_DIR:-${BASE_WORKSPACE}/${PROJECT_KEY}}"
else
  echo "Unknown system, defaulting to current dir"
  export BASE_WORKSPACE="$(pwd)"
  export OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)}"
fi

echo "  Starting DataOps Pipeline (DCM)"
echo "=================================================="
echo "   SOURCE_DATABASE:         $SOURCE_DATABASE"
echo "   SOURCE_SCHEMA:           $SOURCE_SCHEMA"
echo "   PROJECT_KEY:             $PROJECT_KEY"
echo "   CONNECTION_NAME:         $CONNECTION_NAME"
echo "   DCM_PROJECT_IDENTIFIER:  $DCM_PROJECT_IDENTIFIER"
echo "   DCM_TARGET:              $DCM_TARGET"
echo "   RELEASE_NUM:             $RELEASE_NUM"
echo "=================================================="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Step 1: Extracting Snowflake schema dependencies..."
if [[ -f "$SCRIPT_DIR/snowflake-extract-dependencies_v1.sh" ]]; then
    "$SCRIPT_DIR/snowflake-extract-dependencies_v1.sh" \
        --SOURCE_DATABASE="$SOURCE_DATABASE" \
        --SOURCE_SCHEMA="$SOURCE_SCHEMA" \
        --OUTPUT_DIR="$OUTPUT_DIR" \
        --CONNECTION_NAME="$CONNECTION_NAME"
    echo "Dependencies extraction completed"
else
    echo "Error: snowflake-extract-dependencies_v1.sh not found"
    exit 1
fi
echo ""

echo "Step 2: DCM Analyze + Plan + Deploy..."
if [[ -f "$SCRIPT_DIR/snowflake-deploy-dcm_v1.sh" ]]; then
    "$SCRIPT_DIR/snowflake-deploy-dcm_v1.sh" \
        --PROJECT_IDENTIFIER="$DCM_PROJECT_IDENTIFIER" \
        --CONNECTION_NAME="$CONNECTION_NAME" \
        --TARGET="$DCM_TARGET" \
        --ALIAS="release-$RELEASE_NUM" \
        --PROJECT_DIR="$OUTPUT_DIR"
    echo "DCM deployment completed"
else
    echo "Error: snowflake-deploy-dcm_v1.sh not found"
    exit 1
fi
echo ""

echo "Step 3: Running SQL validation tests..."
if [[ -f "$SCRIPT_DIR/sql_validation_v4.sh" ]]; then
    "$SCRIPT_DIR/sql_validation_v4.sh" \
        --CLONE_SCHEMA="$SOURCE_SCHEMA" \
        --CLONE_DATABASE="$SOURCE_DATABASE" \
        --RELEASE_NUM="$RELEASE_NUM" \
        --CONNECTION_NAME="$CONNECTION_NAME" \
        --TEST_FILE="$TEST_FILE" \
        --FAKE_RUN="$FAKE_RUN"
    echo "SQL validation completed"
else
    echo "Error: sql_validation_v4.sh not found"
    exit 1
fi
echo ""

echo "DataOps Pipeline completed successfully!"
echo "=================================================="
echo "   Dependencies extracted"
echo "   DCM deployed (analyze -> plan -> deploy)"
echo "   SQL validation executed"
echo "=================================================="
