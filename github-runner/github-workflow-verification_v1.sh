#!/bin/bash

# github-workflow-verification_v1.sh
# shasum -a 256 .github/workflows/update-local-repo.yml
# Validates the SHA256 hash of the update-local-repo.yml GitHub Actions workflow file

# --- Runtime detection ---
if [[ -f /.dockerenv ]] || grep -qE '/docker/|/lxc/' /proc/1/cgroup 2>/dev/null; then
  echo "Running inside Docker container"
  WORKFLOW_FILE="/home/docker/actions-runner/_work/$PROJECT_KEY/$PROJECT_KEY/.github/workflows/update-local-repo.yml"
elif [[ "$(uname)" == "Darwin" ]]; then
  echo "Running on macOS"
  WORKFLOW_FILE="$HOME/workspace/mother-of-all-Projects/.github/workflows/update-local-repo.yml"
else
  echo "Unknown system, defaulting to current dir"
  WORKFLOW_FILE="$(pwd)/.github/workflows/update-local-repo.yml"
fi


# === CONFIGURATION ===
EXPECTED_HASH="27774a1330bde81a24528b01537f61961b32cf4b1173ea353e0c89c4df0da37a"

# === VALIDATION ===

if [[ ! -f "$WORKFLOW_FILE" ]]; then
  echo "❌ ERROR: Workflow file not found: $WORKFLOW_FILE"
  exit 1
fi

ACTUAL_HASH=$(sha256sum "$WORKFLOW_FILE" | awk '{print $1}')

echo "Verifying workflow integrity..."
echo "→ Expected SHA256: $EXPECTED_HASH"
echo "→ Actual   SHA256: $ACTUAL_HASH"

if [[ "$ACTUAL_HASH" == "$EXPECTED_HASH" ]]; then
  echo "✅ Workflow verification successful: integrity confirmed."
  exit 0
else
  echo "❌ Workflow verification failed: hash mismatch."
  exit 1
fi
