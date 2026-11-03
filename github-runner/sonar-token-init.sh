#!/bin/bash

# -----------------------------------------------------------------------------
# Auto-generates a SonarQube analysis token at runner startup.
# Eliminates the need to manually manage SONAR_TOKEN secrets.
# Requires SONAR_HOST, SONAR_ADMIN_USER, SONAR_ADMIN_PASS env vars.
# Writes SONAR_TOKEN=... to $SONAR_ENV_FILE (default ~/.sonar_env).
# -----------------------------------------------------------------------------

set +e
LIB="$(dirname "${BASH_SOURCE[0]}")/lib.sh"; [[ -f "$LIB" ]] || LIB=/usr/local/bin/lib.sh
# shellcheck source=/dev/null
source "$LIB"
set -u

SONAR_HOST="${SONAR_HOST:-http://sonarqube:9000}"
SONAR_ADMIN_USER="${SONAR_ADMIN_USER:-admin}"
SONAR_ADMIN_PASS="${SONAR_ADMIN_PASS:-ThisIsNotSecure1234!}"
SONAR_ENV_FILE="${SONAR_ENV_FILE:-$HOME/.sonar_env}"
TOKEN_NAME="runner-${RUNNER_NAME:-${GITHUB_REPO:-default}}-$(date +%Y%m%d)"

log_info "Waiting for SonarQube at $SONAR_HOST..."
for _ in $(seq 1 60); do
  STATUS=$(curl -sf "$SONAR_HOST/api/system/status" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || true)
  if [[ "$STATUS" == "UP" ]]; then
    log_info "SonarQube is UP."
    break
  fi
  sleep 5
done

if [[ "$STATUS" != "UP" ]]; then
  log_warn "SonarQube not ready after 5 minutes. Skipping token generation."
  exit 0
fi

# Fresh instance (new volume, CI): replace the default admin/admin password once.
if ! curl -sf -u "$SONAR_ADMIN_USER:$SONAR_ADMIN_PASS" "$SONAR_HOST/api/authentication/validate" | grep -q '"valid":true' \
  && curl -sf -u "$SONAR_ADMIN_USER:admin" "$SONAR_HOST/api/authentication/validate" | grep -q '"valid":true'; then
  if curl -sf -u "$SONAR_ADMIN_USER:admin" -X POST "$SONAR_HOST/api/users/change_password" \
    --data-urlencode "login=$SONAR_ADMIN_USER" --data-urlencode "previousPassword=admin" \
    --data-urlencode "password=$SONAR_ADMIN_PASS" >/dev/null; then
    log_info "Changed default admin password."
  else
    log_warn "Could not change default admin password."
  fi
fi

EXISTING=$(curl -sf -u "$SONAR_ADMIN_USER:$SONAR_ADMIN_PASS" "$SONAR_HOST/api/user_tokens/search" 2>/dev/null | python3 -c "
import sys, json
tokens = json.load(sys.stdin).get('userTokens', [])
for t in tokens:
    if t['name'] == '$TOKEN_NAME':
        print('exists')
        break
" 2>/dev/null || true)

if [[ "$EXISTING" == "exists" ]]; then
  curl -sf -u "$SONAR_ADMIN_USER:$SONAR_ADMIN_PASS" -X POST "$SONAR_HOST/api/user_tokens/revoke" -d "name=$TOKEN_NAME" > /dev/null 2>&1 || true
fi

RESPONSE=$(curl -sf -u "$SONAR_ADMIN_USER:$SONAR_ADMIN_PASS" -X POST "$SONAR_HOST/api/user_tokens/generate" \
  -d "name=$TOKEN_NAME" \
  -d "type=GLOBAL_ANALYSIS_TOKEN" 2>&1)

NEW_TOKEN=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null || true)

if [[ -n "$NEW_TOKEN" ]]; then
  export SONAR_TOKEN="$NEW_TOKEN"
  # Overwrite (not append) so only the current token is on disk; owner-only.
  ( umask 077; echo "SONAR_TOKEN=$NEW_TOKEN" > "$SONAR_ENV_FILE" )
  log_info "Auto-generated SONAR_TOKEN for project scope: $TOKEN_NAME"
  # Revoke older runner-* tokens so they don't pile up (one per day/runner).
  curl -sf -u "$SONAR_ADMIN_USER:$SONAR_ADMIN_PASS" "$SONAR_HOST/api/user_tokens/search" 2>/dev/null \
    | jq -r '.userTokens[].name' | grep '^runner-' | grep -vx "$TOKEN_NAME" \
    | while read -r OLD; do
        curl -sf -u "$SONAR_ADMIN_USER:$SONAR_ADMIN_PASS" -X POST "$SONAR_HOST/api/user_tokens/revoke" \
          --data-urlencode "name=$OLD" >/dev/null && log_info "Revoked old token: $OLD"
      done || true
else
  # Never print the response body: on partial success it can contain the token.
  log_error "Failed to generate SONAR_TOKEN for $TOKEN_NAME (check SonarQube admin credentials)."
  exit 1
fi
