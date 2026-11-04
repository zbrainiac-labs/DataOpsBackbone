#!/bin/bash
# shellcheck disable=SC2329  # helpers are invoked indirectly via check/retry
# Smoke test for the observability stack (otel-collector, VictoriaTraces,
# VictoriaMetrics, Grafana). Needs curl and jq on the host.
# Usage: local-ci/observability-smoke.sh [--quick]
#   --quick   health endpoints only (used by start.sh); no test data written
# The full run sends one synthetic trace (service "smoke-test") and checks the
# Jaeger-parity features: services, operations, tag search, duration filters,
# exact long durations, spanmetrics buckets/labels, data sources and dashboards.
set -Eeuo pipefail

QUICK=false
for arg in "$@"; do
  case "$arg" in
    --quick) QUICK=true ;;
    -h|--help) sed -n '3,9p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

COLLECTOR=http://127.0.0.1:4318
COLLECTOR_HEALTH=http://127.0.0.1:13133
VT=http://127.0.0.1:10428
VM=http://127.0.0.1:8428
GRAFANA=http://127.0.0.1:3000
JAEGER_API=$VT/select/jaeger/api

FAILED=0
ok()   { echo "  OK    $*"; }
fail() { echo "  FAIL  $*"; FAILED=1; }
check() {  # check LABEL CMD...
  local label=$1; shift
  if "$@" >/dev/null 2>&1; then ok "$label"; else fail "$label"; fi
}
# retry N CMD...: re-run CMD every 2s until it succeeds (ingest/flush delay)
retry() {
  local n=$1; shift
  for ((i = 0; i < n; i++)); do "$@" >/dev/null 2>&1 && return 0; sleep 2; done
  return 1
}

echo "Health"
check "otel-collector  $COLLECTOR_HEALTH" curl -sf "$COLLECTOR_HEALTH/"
check "VictoriaTraces  $VT/health"        curl -sf "$VT/health"
check "VictoriaMetrics $VM/health"        curl -sf "$VM/health"
check "Grafana         $GRAFANA/api/health" curl -sf "$GRAFANA/api/health"
if [[ "$QUICK" == true || "$FAILED" != 0 ]]; then
  [[ "$FAILED" == 0 ]] || echo "Observability health check failed (pipelines still run; tracing is fail-open)"
  exit "$FAILED"
fi

# --- Synthetic trace: root "pipeline" of exactly 25 min, failed child step
SERVICE=smoke-test
RUN=$(date +%s)
TRACE_ID=$(printf '%032x' "$RUN")
ROOT_ID=$(printf '%016x' "$RUN")
STEP_ID=$(printf '%016x' $((RUN + 1)))
END_NS=$(( $(date +%s) * 1000000000 ))
START_NS=$(( END_NS - 25 * 60 * 1000000000 ))
STEP_START_NS=$(( END_NS - 30 * 1000000000 ))
attr() { printf '{"key":"%s","value":{"stringValue":"%s"}}' "$1" "$2"; }
COMMON="$(attr vcs.repository $SERVICE),$(attr cicd.job scan),$(attr sf.database SMOKE_DB),$(attr cicd.pipeline.run.id "$RUN")"
PAYLOAD=$(cat <<EOF
{"resourceSpans":[{"resource":{"attributes":[$(attr service.name $SERVICE)]},
 "scopeSpans":[{"spans":[
  {"traceId":"$TRACE_ID","spanId":"$ROOT_ID","name":"pipeline","kind":1,
   "startTimeUnixNano":"$START_NS","endTimeUnixNano":"$END_NS",
   "attributes":[$COMMON,$(attr cicd.pipeline.result success)]},
  {"traceId":"$TRACE_ID","spanId":"$STEP_ID","parentSpanId":"$ROOT_ID","name":"scan.sonar","kind":1,
   "startTimeUnixNano":"$STEP_START_NS","endTimeUnixNano":"$END_NS",
   "attributes":[$COMMON,$(attr exit_code 1)],"status":{"code":2,"message":"exit 1"}}
 ]}]}]}
EOF
)

echo "Ingest (service=$SERVICE, trace=$TRACE_ID)"
check "OTLP/HTTP accepted by collector" curl -sf -X POST -H 'Content-Type: application/json' \
  --data "$PAYLOAD" "$COLLECTOR/v1/traces"

echo "Traces (Jaeger API parity)"
has_service()   { curl -sf "$JAEGER_API/services" | jq -e --arg s "$SERVICE" '.data | index($s)'; }
has_operation() { curl -sf "$JAEGER_API/services/$SERVICE/operations" | jq -e '[.data[].name? // .data[]] | index("scan.sonar")'; }
search() {  # search EXTRA_QUERY -> number of matching traces with our trace id
  curl -sfG "$JAEGER_API/traces" --data-urlencode "service=$SERVICE" --data-urlencode "lookback=2h" \
    --data-urlencode "limit=20" "$@" | jq --arg t "$TRACE_ID" '[.data[] | select(.traceID == $t)] | length'
}
found()     { [[ "$(search "$@")" -ge 1 ]]; }
not_found() { [[ "$(search "$@")" -eq 0 ]]; }
root_duration_exact() {  # Jaeger API reports microseconds
  curl -sf "$JAEGER_API/traces/$TRACE_ID" \
    | jq -e '[.data[].spans[] | select(.operationName == "pipeline") | .duration] == [1500000000]'
}
eventually() {  # eventually LABEL CMD...: like check, with ingest/index delay
  local label=$1; shift
  if retry 15 "$@"; then ok "$label"; else fail "$label"; fi
}
eventually "service listed" has_service
eventually "operation scan.sonar listed" has_operation
eventually "tag search cicd.job=scan" found --data-urlencode 'tags={"cicd.job":"scan"}'
check "tag search excludes cicd.job=deploy" not_found --data-urlencode 'tags={"cicd.job":"deploy"}'
eventually "minDuration=24m finds the 25m trace" found --data-urlencode "minDuration=24m"
check "maxDuration=1m skips the 25m root" not_found --data-urlencode "operation=pipeline" --data-urlencode "maxDuration=1m"
eventually "25m root span keeps its exact duration" root_duration_exact

echo "Metrics (spanmetrics in VictoriaMetrics)"
promql() { curl -sfG "$VM/api/v1/query" --data-urlencode "query=$1" | jq -e '.data.result | length > 0'; }
SEL="service_name=\"$SERVICE\",span_name=\"pipeline\""
# Spanmetrics flush every 15s (eventually waits up to 30s)
eventually "calls_total series" promql "traces_span_metrics_calls_total{$SEL}"
check "25m span counted in the 30m bucket" promql "traces_span_metrics_duration_seconds_bucket{$SEL,le=\"1800\"} > 0"
check "25m span not in the 20m bucket" promql "absent(traces_span_metrics_duration_seconds_bucket{$SEL,le=\"1200\"} > 0)"
check "labels vcs_repository/cicd_job/sf_database" \
  promql "traces_span_metrics_calls_total{$SEL,vcs_repository=\"$SERVICE\",cicd_job=\"scan\",sf_database=\"SMOKE_DB\"}"
check "error status on the failed step" \
  promql "traces_span_metrics_calls_total{service_name=\"$SERVICE\",span_name=\"scan.sonar\",status_code=\"STATUS_CODE_ERROR\"}"
check "trace-only attribute not a label" promql "absent(traces_span_metrics_calls_total{cicd_pipeline_run_id!=\"\"})"

echo "Grafana"
PASS=${GRAFANA_ADMIN_PASSWORD:-$(grep -m1 '^GRAFANA_ADMIN_PASSWORD=' "$(dirname "$0")/../.env" 2>/dev/null | cut -d= -f2- || true)}
G=(curl -sf -u "admin:$PASS")
ds_ok() { "${G[@]}" "$GRAFANA/api/datasources/uid/$1/health" | jq -e '.status == "OK"'; }
dash_in_folder() { "${G[@]}" "$GRAFANA/api/dashboards/uid/$1" | jq -e '.meta.folderTitle == "DataOps" and .meta.provisioned'; }
panel_has_data() {
  "${G[@]}" -X POST -H 'Content-Type: application/json' "$GRAFANA/api/ds/query" --data \
    "{\"from\":\"now-1h\",\"to\":\"now\",\"queries\":[{\"refId\":\"A\",\"datasource\":{\"uid\":\"victoriametrics\"},\"expr\":\"sum(increase(traces_span_metrics_calls_total{span_name=\\\"pipeline\\\"}[1h]))\",\"instant\":true}]}" \
    | jq -e '.results.A.frames | length > 0'
}
check "data source victoriametrics healthy" ds_ok victoriametrics
check "data source victoriatraces healthy" ds_ok victoriatraces
for uid in dataops-pipeline-overview dataops-jobs-steps dataops-traces; do
  check "dashboard $uid provisioned in DataOps" dash_in_folder "$uid"
done
check "pipeline-count panel query returns data" panel_has_data
check "anonymous viewer can open dashboards" curl -sf "$GRAFANA/api/dashboards/uid/dataops-pipeline-overview"

echo
if [[ "$FAILED" == 0 ]]; then echo "Observability smoke test passed"; else echo "Observability smoke test FAILED"; fi
exit "$FAILED"
