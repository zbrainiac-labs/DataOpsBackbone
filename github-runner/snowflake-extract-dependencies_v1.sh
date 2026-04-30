#!/bin/bash

# -----------------------------------------------------------------------------
# Extract Snowflake schema dependencies using `snow` CLI
# -----------------------------------------------------------------------------
# Usage:
# ./snowflake-extract-dependencies_v1.sh \
#   --SOURCE_DATABASE=DataOps \
#   --SOURCE_SCHEMA=IOT_CLONE_42 \
#   [--OUTPUT_DIR=/home/docker/actions-runner/_work/my_project/my_project] \
#   --CONNECTION_NAME=ci_user_test
#
# ./snowflake-extract-dependencies_v1.sh --SOURCE_DATABASE=DATAOPS --SOURCE_SCHEMA=IOT_RAW_v001 --OUTPUT_DIR=/tmp --CONNECTION_NAME=sfseeurope-svc_cicd
#
# -----------------------------------------------------------------------------

set +e

# --- Default values ---
OUTPUT_FILE_NAME="output_dependencies.csv"

# Parse arguments
for ARG in "$@"; do
  case $ARG in
    --SOURCE_DATABASE=*)
      SOURCE_DATABASE="${ARG#*=}" ;;
    --SOURCE_SCHEMA=*)
      SOURCE_SCHEMA="${ARG#*=}" ;;
    --OUTPUT_DIR=*)
      OUTPUT_DIR="${ARG#*=}" ;;
    --CONNECTION_NAME=*)
      CONNECTION_NAME="${ARG#*=}" ;;
    *)
      echo "❌ Unknown argument: $ARG"
      echo "Usage: $0 --SOURCE_DATABASE=... --SOURCE_SCHEMA=... --OUTPUT_DIR=... --CONNECTION_NAME=..."
      exit 1
      ;;
  esac
done

# Validate required inputs
if [[ -z "$SOURCE_DATABASE" || -z "$SOURCE_SCHEMA" || -z "$CONNECTION_NAME" ]]; then
  echo "❌ Missing required arguments."
  echo "Required: --SOURCE_DATABASE --SOURCE_SCHEMA --CONNECTION_NAME [--OUTPUT_DIR=...]"
  exit 1
fi

# Set default OUTPUT_DIR if not provided
if [[ -z "$OUTPUT_DIR" ]]; then
  if [[ -z "$PROJECT_KEY" ]]; then
    echo "❌ PROJECT_KEY is not set, and no --OUTPUT_DIR provided."
    exit 1
  fi
  OUTPUT_DIR="/home/docker/actions-runner/_work/${PROJECT_KEY}/${PROJECT_KEY}"
fi

FINAL_OUTPUT_DIR="${OUTPUT_DIR}/dependencies"


# Ensure output directory exists
mkdir -p "$FINAL_OUTPUT_DIR"

echo "Extracting dependencies for schema: $SOURCE_DATABASE.$SOURCE_SCHEMA"
echo "Using connection: $CONNECTION_NAME"
echo "Output directory: $FINAL_OUTPUT_DIR"
echo "Output file: $FINAL_OUTPUT_FILE_DEPENDENCIES"

# Run the dependency extraction SQL
echo "Extracting dependencies..."
timeout 120 snow sql -c "$CONNECTION_NAME" --format=csv -q "
SELECT
    dep_obj.REFERENCED_DATABASE AS base_database,
    dep_obj.REFERENCED_SCHEMA AS base_schema,
    dep_obj.REFERENCED_OBJECT_NAME AS base_object,
    dep_obj.REFERENCED_OBJECT_ID AS base_object_id,
    dep_obj.REFERENCING_DATABASE AS referenced_database,
    dep_obj.REFERENCING_SCHEMA AS referenced_schema,
    dep_obj.REFERENCING_OBJECT_NAME AS referenced_object,
    dep_obj.REFERENCING_OBJECT_DOMAIN AS referenced_object_type,
    dep_obj.REFERENCING_OBJECT_ID AS referenced_object_id,
    CASE
        WHEN dep_obj.REFERENCED_DATABASE <> dep_obj.REFERENCING_DATABASE THEN 'cross_db_true'
        ELSE 'cross_db_false'
    END AS cross_db,
    CASE
        WHEN dep_obj.REFERENCED_SCHEMA <> dep_obj.REFERENCING_SCHEMA
             AND LEFT(dep_obj.REFERENCED_SCHEMA, POSITION('_' IN dep_obj.REFERENCED_SCHEMA) - 1)
              <> LEFT(dep_obj.REFERENCING_SCHEMA, POSITION('_' IN dep_obj.REFERENCING_SCHEMA) - 1)
        THEN 'cross_schema_true'
        ELSE 'cross_schema_false'
    END AS cross_schema,
    CASE
        WHEN dep_obj.REFERENCED_DATABASE <> dep_obj.REFERENCING_DATABASE AND dep_obj.REFERENCED_SCHEMA LIKE 'REF_%' THEN 'cross_db_ref_true'
        ELSE 'cross_db_ref_false'
    END AS cross_db_ref,
    CASE
        WHEN dep_obj.REFERENCED_SCHEMA <> dep_obj.REFERENCING_SCHEMA AND dep_obj.REFERENCED_SCHEMA LIKE 'REF_%' THEN 'cross_schema_ref_true'
        ELSE 'cross_schema_ref_false'
    END AS cross_schema_ref
  FROM SNOWFLAKE.ACCOUNT_USAGE.OBJECT_DEPENDENCIES dep_obj
   WHERE dep_obj.referenced_database = '$SOURCE_DATABASE';" > "$FINAL_OUTPUT_DIR/deps.csv"

if [ $? -eq 0 ]; then
  echo "✅ Dependencies written to $FINAL_OUTPUT_DIR/deps.csv"
else
  echo "❌ Error writing output to $FINAL_OUTPUT_DIR/deps.csv"
  exit 1
fi


echo "Extracting DDL..."
{
  echo "-- ============================================================"
  echo "-- DDL extract: $SOURCE_DATABASE"
  echo "-- Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "-- Connection: $CONNECTION_NAME"
  echo "-- ============================================================"
  snow sql -c $CONNECTION_NAME -q "
SELECT GET_DDL('DATABASE','$SOURCE_DATABASE')" --format=csv | tail -n +2 | tr -d '"'
} > $FINAL_OUTPUT_DIR/ddl.sql

echo "Done: $FINAL_OUTPUT_DIR/deps.csv + $FINAL_OUTPUT_DIR/ddl.sql"

if [[ -d "/home/docker/dependencies" ]]; then
  cp -f "$FINAL_OUTPUT_DIR/deps.csv" "$FINAL_OUTPUT_DIR/ddl.sql" /home/docker/dependencies/ 2>/dev/null && echo "Copied to shared dependencies volume" || true
fi