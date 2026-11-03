#!/bin/bash

# -----------------------------------------------------------------------------
# Decodes SNOW_CONFIG_B64 into ~/.snowflake/config.toml
# Extracts CONNECTION_NAME from the config if not already set
# Checks PAT expiry and warns if < 30 days remaining
# -----------------------------------------------------------------------------

set -Eeuo pipefail
LIB="$(dirname "${BASH_SOURCE[0]}")/lib.sh"; [[ -f "$LIB" ]] || LIB=/usr/local/bin/lib.sh
# shellcheck source=/dev/null
source "$LIB"

SNOW_DIR="$HOME/.snowflake"
mkdir -p "$SNOW_DIR"

if [[ -z "${SNOW_CONFIG_B64:-}" ]]; then
  log_error "Missing required environment variable SNOW_CONFIG_B64."
  exit 1
fi

log_info "Decoding Snowflake config..."
echo "$SNOW_CONFIG_B64" | base64 --decode > "$SNOW_DIR/config.toml"
chmod 600 "$SNOW_DIR/config.toml"

if [[ -z "${CONNECTION_NAME:-}" || "$CONNECTION_NAME" == "default_value_here" ]]; then
  CONNECTION_NAME=$(grep -oP '^\[connections\.\K[^\]]+' "$SNOW_DIR/config.toml" | head -1)
  if [[ -n "$CONNECTION_NAME" ]]; then
    log_info "Auto-detected CONNECTION_NAME: $CONNECTION_NAME"
    export CONNECTION_NAME
  else
    log_error "Could not auto-detect CONNECTION_NAME from config.toml"
    exit 1
  fi
fi

PAT_TOKEN=$(grep -A10 "\[connections\.$CONNECTION_NAME\]" "$SNOW_DIR/config.toml" | grep 'token' | head -1 | sed 's/.*= *"\(.*\)"/\1/')
if [[ -n "$PAT_TOKEN" ]]; then
  PAYLOAD=$(echo "$PAT_TOKEN" | cut -d'.' -f2)
  PADDED=$(echo "$PAYLOAD" | awk '{while(length%4)$0=$0"=";print}')
  EXP=$(echo "$PADDED" | base64 --decode 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('exp',''))" 2>/dev/null || true)
  if [[ -n "$EXP" && "$EXP" =~ ^[0-9]+$ ]]; then
    NOW=$(date +%s)
    DAYS_LEFT=$(( (EXP - NOW) / 86400 ))
    if [[ "$DAYS_LEFT" -le 0 ]]; then
      log_error "PAT has EXPIRED! Renew immediately."
      exit 1
    elif [[ "$DAYS_LEFT" -le 30 ]]; then
      log_warn "PAT expires in $DAYS_LEFT days. Renew soon."
    else
      log_info "PAT valid for $DAYS_LEFT more days."
    fi
  fi
fi
