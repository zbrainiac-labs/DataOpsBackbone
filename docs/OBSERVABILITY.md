# Observability

## Pipeline tracing (OpenTelemetry)

Every `run:` step in `dataops-pipeline.yml` is wrapped in `otel_step` (`github-runner/lib.sh`): it logs a begin/end line with exit code and duration, and exports one span per step. All jobs of one run share a trace (trace id derived from `run_id` + attempt):

```
pipeline <repo>          overall result (finish job)
├── job <name>           full job duration incl. checkout/connect, result, runner name
│   ├── queue <name>     time waiting for a runner (GitHub API; not in local-ci)
│   └── <step>           e.g. scan.sonar, deploy.dcm — exit code + duration
```

```bash
./start.sh                           # Jaeger starts by default; UI on http://localhost:16686 (one service per project, e.g. project-one)
./start.sh --no-observability        # without Jaeger; runners get no OTLP endpoint
```

- One container (`jaegertracing/jaeger` v2, config in `jaeger/config.yaml`, Badger storage, 7-day retention) on its own `otelnet` network; SonarQube and Postgres are not reachable from it.
- Fail-open: with `--no-observability` the runners have no OTLP endpoint and no spans are sent; a stopped Jaeger never fails a step.
- Disable per consumer with the workflow input `OTEL_ENABLED: false`.
- `local-ci/run.sh` sends traces to Jaeger automatically when it is running.

