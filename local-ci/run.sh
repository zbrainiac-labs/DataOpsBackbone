#!/bin/bash
# -----------------------------------------------------------------------------
# Simulate a GitHub Actions run locally -- no commit or push required.
#
# Runs a consumer project's own workflow with nektos/act inside the runner
# image. All references to zbrainiac-labs/DataOpsBackbone@main (reusable
# workflow + composite actions) resolve to THIS working copy, and the runner
# image is rebuilt from local sources, so uncommitted changes are tested.
#
# Usage:
#   local-ci/run.sh [--project=../project-one] [--dry-run|--full] [--no-build]
#                   [-- <extra act args>]
#
#   --project   consumer repo containing a workflow that calls dataops-pipeline.yml
#               (default: ../project-one)
#   --dry-run   prepare + scan only, no Snowflake changes (default)
#   --full      full pipeline incl. deploy to clone schema (GitHub Release is skipped)
#   --no-build  reuse the existing brainiac/local-github-runner:act image
#
# Requires: act, docker, python3 + pyyaml, running SonarQube stack, and either
# GITHUB_TOKEN set or gh logged in. Or run it containerized (no host tools):
#   GITHUB_TOKEN=$(gh auth token) docker compose --profile local-ci run --rm local-ci --dry-run
# Snowflake auth: PAT path only (OIDC is not available locally). Credentials come
# from SNOW_CONFIG_B64 (env) or SNOW_ACCOUNT/SNOW_USER/SNOW_PAT in .env.
# -----------------------------------------------------------------------------
set -Eeuo pipefail

BACKBONE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$BACKBONE/../project-one"
DRY_RUN=true
BUILD=true
ACT_ARGS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --project=*) PROJECT="${1#*=}" ;;
    --dry-run) DRY_RUN=true ;;
    --full) DRY_RUN=false ;;
    --no-build) BUILD=false ;;
    --) shift; ACT_ARGS=("$@"); break ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
  shift
done

PROJECT="$(cd "$PROJECT" && pwd)"
PROJECT_NAME="$(basename "$PROJECT")"
IMAGE=brainiac/local-github-runner:act

for cmd in act docker python3; do
  command -v "$cmd" >/dev/null || { echo "ERROR: $cmd not found"; exit 1; }
done

NETWORK=$(docker network ls --format '{{.Name}}' | grep -m1 'sonarnet$' || true)
[[ -n "$NETWORK" ]] || { echo "ERROR: sonarnet network not found -- run ./start.sh first"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
chmod 700 "$TMP"

# --- 1. Runner image from local sources (separate tag, live runners untouched)
if [[ "$BUILD" == "true" ]]; then
  case "$(uname -m)" in
    x86_64) TARGETARCH=amd64 ;;
    arm64|aarch64) TARGETARCH=arm64 ;;
    *) echo "Unsupported architecture"; exit 1 ;;
  esac
  echo "Building $IMAGE from local sources..."
  docker build -q --build-arg TARGETARCH="$TARGETARCH" \
    -t "$IMAGE" -f "$BACKBONE/github-runner/Dockerfile" "$BACKBONE/github-runner" >/dev/null
fi

# --- 2. Caller workflow: the project's own pipeline inputs, DRY_RUN overridden
python3 - "$PROJECT" "$DRY_RUN" "$TMP/caller.yml" <<'PY'
import glob, sys, yaml
project, dry_run, out = sys.argv[1], sys.argv[2] == "true", sys.argv[3]
for path in sorted(glob.glob(f"{project}/.github/workflows/*.y*ml")):
    wf = yaml.safe_load(open(path))
    for job in (wf.get("jobs") or {}).values():
        if "dataops-pipeline.yml" in str(job.get("uses", "")):
            job["with"] = {**job.get("with", {}), "DRY_RUN": dry_run, "USE_OIDC": False}
            caller = {"name": "local-ci", "on": {"workflow_dispatch": {}},
                      "permissions": wf.get("permissions", {}), "jobs": {"pipeline": job}}
            yaml.safe_dump(caller, open(out, "w"), sort_keys=False)
            print(f"Using pipeline inputs from {path}")
            sys.exit(0)
sys.exit(f"ERROR: no workflow calling dataops-pipeline.yml found in {project}")
PY

cat > "$TMP/event.json" <<JSON
{"repository": {"name": "$PROJECT_NAME", "full_name": "zbrainiac-labs/$PROJECT_NAME",
                "owner": {"login": "zbrainiac-labs"}}}
JSON

# --- 3. Secrets (never echoed; files are removed on exit)
SNOW_CONFIG_B64="${SNOW_CONFIG_B64:-}"
if [[ -z "$SNOW_CONFIG_B64" && -f "$BACKBONE/.env" ]]; then
  SNOW_CONFIG_B64=$(
    set -a
    # shellcheck source=/dev/null
    source "$BACKBONE/.env"
    [[ -n "${SNOW_ACCOUNT:-}" && -n "${SNOW_USER:-}" && -n "${SNOW_PAT:-}" ]] || exit 0
    printf '[connections.%s]\naccount = "%s"\nuser = "%s"\nrole = "%s"\ndatabase = "%s"\nschema = "%s"\nwarehouse = "%s"\nauthenticator = "programmatic_access_token"\ntoken = "%s"\n' \
      "${CONNECTION_NAME:-default}" "$SNOW_ACCOUNT" "$SNOW_USER" "${SNOW_ROLE:-CICD}" "${SNOW_DATABASE:-DATAOPS}" \
      "${SNOW_SCHEMA:-IOT_RAW_V001}" "${SNOW_WAREHOUSE:-MD_TEST_WH}" "$SNOW_PAT" | base64 | tr -d '\n'
  )
fi
[[ -n "$SNOW_CONFIG_B64" ]] || { echo "ERROR: no Snowflake credentials (SNOW_CONFIG_B64 or SNOW_* in .env)"; exit 1; }

{
  echo "SNOW_CONFIG_B64=$SNOW_CONFIG_B64"
  echo "GITHUB_TOKEN=${GITHUB_TOKEN:-$(gh auth token 2>/dev/null || true)}"
} > "$TMP/secrets"

# Reuse the shared Sonar token created by the sonar-init service.
SONAR_VOL=$(docker volume ls --format '{{.Name}}' | grep -m1 'sonar_env$' || true)
SONAR_TOKEN=""
if [[ -n "$SONAR_VOL" ]]; then
  SONAR_TOKEN=$(docker run --rm -v "$SONAR_VOL:/sonar:ro" --entrypoint sh "$IMAGE" \
    -c 'grep -m1 "^SONAR_TOKEN=" /sonar/.sonar_env | cut -d= -f2-' 2>/dev/null || true)
fi
[[ -n "$SONAR_TOKEN" ]] || echo "WARNING: no SONAR_TOKEN in sonar_env volume (sonar-init not run?); Sonar scan will fail"
echo "SONAR_TOKEN=$SONAR_TOKEN" > "$TMP/env"

# act always reports run_number=1; make each local run unique so DCM version
# aliases (release-<n>-<attempt>), clone schemas and trace ids don't collide.
RUN_SEQ=$(date +%s)
{ echo "GITHUB_RUN_NUMBER=$RUN_SEQ"; echo "GITHUB_RUN_ID=$RUN_SEQ"; } >> "$TMP/env"

# Send traces to Jaeger if it is running (default with ./start.sh)
if [[ -n "$(docker ps -q --filter label=com.docker.compose.service=jaeger)" ]]; then
  echo "OTEL_EXPORTER_OTLP_ENDPOINT=host.docker.internal:4317" >> "$TMP/env"
  echo "Tracing to Jaeger: http://localhost:16686 (service = project name, e.g. $PROJECT_NAME)"
fi

# --- 4. Run
LOG_DIR="$BACKBONE/archive/local-ci"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/$(date +%Y%m%dT%H%M%S)-$PROJECT_NAME.log"
echo "Running $PROJECT_NAME (DRY_RUN=$DRY_RUN) -- log: $LOG"

set +e
act workflow_dispatch \
  -C "$PROJECT" \
  -W "$TMP/caller.yml" \
  -e "$TMP/event.json" \
  -P self-hosted="$IMAGE" --pull=false \
  --local-repository "zbrainiac-labs/DataOpsBackbone@main=$BACKBONE" \
  --network "$NETWORK" \
  --secret-file "$TMP/secrets" \
  --env-file "$TMP/env" \
  ${ACT_ARGS[@]+"${ACT_ARGS[@]}"} 2>&1 | tee "$LOG"
RC=${PIPESTATUS[0]}
set -e

if grep -qE 'squ_[A-Za-z0-9]{20,}|gh[op]_[A-Za-z0-9]{20,}' "$LOG"; then
  echo "ERROR: secret-looking value found in log $LOG"
  RC=1
fi
echo "act exit code: $RC"
exit "$RC"
