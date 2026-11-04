#!/bin/bash
# -----------------------------------------------------------------------------
# Shared helpers for pipeline steps. Loaded automatically in every workflow
# step via BASH_ENV=/usr/local/bin/lib.sh; scripts source it themselves:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# -----------------------------------------------------------------------------

# --- Logging (stderr, so stdout stays clean for data) -------------------------
# Format: 2026-11-02T21:30:00Z INFO  [script] message
# WARN/ERROR also emit a GitHub annotation when running under Actions.
# LOG_TAG overrides the [script] tag (default: name of the calling script).
_log() {
  local level=$1; shift
  local tag=${LOG_TAG:-} src
  if [[ -z "$tag" ]]; then  # first caller outside lib.sh; inline workflow steps -> job name
    for src in "${BASH_SOURCE[@]:1}"; do
      [[ "$src" == */lib.sh || "$src" == lib.sh || "$src" == */workflow/*.sh ]] || { tag=$(basename "$src" .sh); break; }
    done
    tag=${tag:-${GITHUB_JOB:-$(basename "$0" .sh)}}
  fi
  printf '%s %-5s [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$level" "$tag" "$*" >&2
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    case "$level" in
      WARN) echo "::warning title=${tag}::$*" >&2 ;;
      ERROR) echo "::error title=${tag}::$*" >&2 ;;
    esac
  fi
  return 0
}
log_info() { _log INFO "$@"; }
log_warn() { _log WARN "$@"; }
log_error() { _log ERROR "$@"; }
# die MSG [EXIT_CODE]  -- log an error and exit (default 1)
die() { log_error "$1"; exit "${2:-1}"; }

# retry [-n attempts] cmd...  -- linear backoff (10s, 20s, ...)
retry() {
  local attempts=3 n=0
  if [[ "${1:-}" == "-n" ]]; then attempts=$2; shift 2; fi
  until "$@"; do
    n=$((n + 1))
    if (( n >= attempts )); then
      log_error "Failed after ${attempts} attempts: $*"
      return 1
    fi
    log_warn "Attempt ${n} failed, retrying in $((n * 10))s..."
    sleep $((n * 10))
  done
}

# --- OpenTelemetry (fail-open: never changes a step's result) -----------------
# Env: OTEL_ENABLED=true, OTEL_EXPORTER_OTLP_ENDPOINT=host:4317 (e.g. otel-collector:4317).
#
# Service name = consumer repo (one trace service per project); the backbone
# workflow is recorded as cicd.pipeline.name.
#
# Span tree per run (ids are derived from run_id + attempt, so every job on any
# runner computes the same ids without passing state around):
#   pipeline                             (finish job)
#   ├── job <name>                       (otel_job_begin / otel_job_end)
#   │   ├── queue <name>                 (finish job, GitHub API; not under act)
#   │   └── <step>                       (otel_step)

_otel_on() {
  [[ "${OTEL_ENABLED:-false}" == "true" && -n "${OTEL_EXPORTER_OTLP_ENDPOINT:-}" ]] && command -v otel-cli >/dev/null
}

_otel_hash() {  # _otel_hash LEN TEXT
  printf '%s' "$2" | sha256sum | cut -c1-"$1"
}

_otel_seed() { printf '%s-%s' "${GITHUB_RUN_ID:-local}" "${GITHUB_RUN_ATTEMPT:-1}"; }
_otel_trace_id() { _otel_hash 32 "$(_otel_seed)"; }
_otel_root_id() { _otel_hash 16 "$(_otel_seed)-root"; }
_otel_job_id() { _otel_hash 16 "$(_otel_seed)-job-${1:-${GITHUB_JOB:-local}}"; }

_otel_ts() {  # epoch nanoseconds -> "seconds.nanoseconds" (otel-cli reads plain integers as seconds)
  local ns=$1
  printf '%d.%09d' "$((ns / 1000000000))" "$((ns % 1000000000))"
}

# otel_span NAME START_NS END_NS STATUS SPAN_ID PARENT_ID [key=value ...]
#   SPAN_ID / PARENT_ID: hex id, or "" for random span id / no parent.
otel_span() {
  _otel_on || return 0
  local name=$1 start=$2 end=$3 status=$4 span_id=$5 parent_id=$6
  shift 6
  local attrs="cicd.pipeline.run.id=${GITHUB_RUN_ID:-local},cicd.pipeline.name=${GITHUB_WORKFLOW:-local},cicd.pipeline.backbone=dataops-pipeline"
  attrs+=",vcs.repository=${GITHUB_REPOSITORY:-local},vcs.ref=${GITHUB_REF_NAME:-local},cicd.job=${GITHUB_JOB:-local}"
  attrs+=",cicd.worker.name=${RUNNER_NAME:-$(hostname)}"
  attrs+=",sf.database=${SOURCE_DATABASE:-},sf.schema=${SOURCE_SCHEMA:-},dcm.target=${DCM_TARGET:-}"
  local kv
  for kv in "$@"; do attrs+=",${kv}"; done
  local -a args=(span --service "${OTEL_SERVICE_NAME:-${PROJECT_KEY:-dataops-pipeline}}" --name "$name"
    --start "$(_otel_ts "$start")" --end "$(_otel_ts "$end")" --attrs "$attrs"
    --timeout 2s --protocol grpc --insecure true --force-trace-id "$(_otel_trace_id)")
  [[ -n "$span_id" ]] && args+=(--force-span-id "$span_id")
  [[ -n "$parent_id" ]] && args+=(--force-parent-span-id "$parent_id")
  [[ "$status" != "0" ]] && args+=(--status-code error --status-description "${OTEL_STATUS_DESC:-exit ${status}}")
  otel-cli "${args[@]}" >/dev/null 2>&1 || true
}

# otel_step NAME -- cmd...   Logs begin/end, runs cmd, emits a span under the job span.
otel_step() {
  local name=$1; shift
  [[ "${1:-}" == "--" ]] && shift
  local start end rc=0
  start=$(date +%s%N)
  echo "::group::[otel] begin ${name}"
  echo "::endgroup::"
  "$@" || rc=$?
  end=$(date +%s%N)
  echo "[otel] end ${name} exit=${rc} duration=$(( (end - start) / 1000000 ))ms"
  otel_span "$name" "$start" "$end" "$rc" "" "$(_otel_job_id)" "exit_code=${rc}"
  return "$rc"
}

# First step of a job: remember the job start for otel_job_end.
otel_job_begin() {
  local now
  now=$(date +%s%N)
  [[ -n "${GITHUB_ENV:-}" ]] && echo "OTEL_JOB_START=${now}" >> "$GITHUB_ENV"
  echo "[otel] job ${GITHUB_JOB:-local} started on ${RUNNER_NAME:-$(hostname)}"
}

# Last step of a job (if: always()):  otel_job_end "${{ job.status }}"
otel_job_end() {
  local status=${1:-success} rc=0
  [[ "$status" == "success" ]] || rc=1
  echo "[otel] job ${GITHUB_JOB:-local} ${status}"
  OTEL_STATUS_DESC="job ${status}" otel_span "job ${GITHUB_JOB:-local}" "${OTEL_JOB_START:-$(date +%s%N)}" \
    "$(date +%s%N)" "$rc" "$(_otel_job_id)" "$(_otel_root_id)" "cicd.job.result=${status}"
}

# Pipeline root span (finish job):  otel_pipeline_end START_NS STATUS(0|1) [key=value ...]
otel_pipeline_end() {
  local start=$1 status=$2
  shift 2
  otel_span "pipeline" "$start" "$(date +%s%N)" "$status" "$(_otel_root_id)" "" "$@"
}

# Queue time per job from the GitHub API (finish job). Needs GH_TOKEN with actions:read.
# Emits "queue <job>" (created_at -> started_at) under each job span. No-op under act.
otel_queue_spans() {
  _otel_on || return 0
  [[ -z "${ACT:-}" && -n "${GH_TOKEN:-}" && -n "${GITHUB_REPOSITORY:-}" ]] || { echo "[otel] queue spans skipped (no GitHub API)"; return 0; }
  local url="${GITHUB_API_URL:-https://api.github.com}/repos/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}/attempts/${GITHUB_RUN_ATTEMPT:-1}/jobs?per_page=100"
  local jobs name key created started secs
  jobs=$(curl -sf -H "Authorization: Bearer ${GH_TOKEN}" -H "Accept: application/vnd.github+json" "$url") \
    || { echo "[otel] queue spans skipped (API call failed)"; return 0; }
  while IFS=$'\t' read -r name created started; do
    [[ -n "$started" && "$started" != "null" ]] || continue
    key="${name##* / }"  # reusable workflow jobs are named "<caller job> / <job>"
    created=$(date -d "$created" +%s%N) started=$(date -d "$started" +%s%N) || continue
    secs=$(( (started - created) / 1000000000 ))
    echo "[otel] queue ${key}: ${secs}s"
    otel_span "queue ${key}" "$created" "$started" 0 "" "$(_otel_job_id "$key")" "cicd.job=${key}" "cicd.job.queue_seconds=${secs}"
  done < <(jq -r '.jobs[] | [.name, .created_at, .started_at] | @tsv' <<<"$jobs")
}
