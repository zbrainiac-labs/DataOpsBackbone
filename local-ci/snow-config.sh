#!/bin/bash
# -----------------------------------------------------------------------------
# Build the base64 Snowflake CLI config (PAT auth) from .env and print it.
# Single source for SNOW_CONFIG_B64: used by local-ci/run.sh and for the
# GitHub secret consumed by the pipeline (USE_OIDC: false).
#
# Usage:
#   bash local-ci/snow-config.sh                     # print to stdout
#   bash local-ci/snow-config.sh | gh secret set SNOW_CONFIG_B64 --org zbrainiac-labs --visibility all
# Env:   ENV_FILE (default: <repo>/.env)
# Needs: SNOW_ACCOUNT, SNOW_USER, SNOW_PAT; optional CONNECTION_NAME, SNOW_ROLE,
#        SNOW_DATABASE, SNOW_SCHEMA, SNOW_WAREHOUSE
# -----------------------------------------------------------------------------
set -Eeuo pipefail

BACKBONE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$BACKBONE/github-runner/lib.sh"

ENV_FILE="${ENV_FILE:-$BACKBONE/.env}"
[[ -f "$ENV_FILE" ]] || die "No env file: $ENV_FILE"

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

missing=()
for v in SNOW_ACCOUNT SNOW_USER SNOW_PAT; do
  [[ -n "${!v:-}" ]] || missing+=("$v")
done
(( ${#missing[@]} == 0 )) || die "Missing in $ENV_FILE: ${missing[*]}"

printf '[connections.%s]\naccount = "%s"\nuser = "%s"\nrole = "%s"\ndatabase = "%s"\nschema = "%s"\nwarehouse = "%s"\nauthenticator = "programmatic_access_token"\ntoken = "%s"\n' \
  "${CONNECTION_NAME:-default}" "$SNOW_ACCOUNT" "$SNOW_USER" "${SNOW_ROLE:-CICD}" "${SNOW_DATABASE:-DATAOPS}" \
  "${SNOW_SCHEMA:-IOT_RAW_V001}" "${SNOW_WAREHOUSE:-MD_TEST_WH}" "$SNOW_PAT" | base64 | tr -d '\n'
