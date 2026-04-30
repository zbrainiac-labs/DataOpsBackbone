#!/bin/bash

# -----------------------------------------------------------------------------
# Auto-generates a SonarQube analysis token at runner startup.
# Eliminates the need to manually manage SONAR_TOKEN secrets.
# Requires SONAR_HOST, SONAR_ADMIN_USER, SONAR_ADMIN_PASS env vars.
# -----------------------------------------------------------------------------

set +e

SONAR_HOST="${SONAR_HOST:-http://sonarqube:9000}"
SONAR_ADMIN_USER="${SONAR_ADMIN_USER:-admin}"
SONAR_ADMIN_PASS="${SONAR_ADMIN_PASS:-ThisIsNotSecure1234!}"
TOKEN_NAME="runner-${RUNNER_NAME:-${GITHUB_REPO:-default}}-$(date +%Y%m%d)"

echo "Waiting for SonarQube at $SONAR_HOST..."
for i in $(seq 1 60); do
  STATUS=$(curl -sf "$SONAR_HOST/api/system/status" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || true)
  if [[ "$STATUS" == "UP" ]]; then
    echo "SonarQube is UP."
    break
  fi
  sleep 5
done

if [[ "$STATUS" != "UP" ]]; then
  echo "SonarQube not ready after 5 minutes. Skipping token generation."
  exit 0
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

if [[ -n "$NEW_TOKEN" && "$NEW_TOKEN" != "" ]]; then
  export SONAR_TOKEN="$NEW_TOKEN"
  echo "SONAR_TOKEN=$NEW_TOKEN" >> "$HOME/.sonar_env"
  echo "Auto-generated SONAR_TOKEN for project scope: $TOKEN_NAME"
else
  echo "Failed to generate SONAR_TOKEN. Response: $RESPONSE"
  exit 1
fi
