"""Static checks for the observability stack (docker-compose, collector, Grafana)."""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

import pytest
import yaml

ROOT = Path(__file__).resolve().parent.parent
OBS = ROOT / "observability"
OBS_SERVICES = ("otel-collector", "victoriatraces", "victoriametrics", "grafana")
TRACE_ONLY = {"cicd.pipeline.run.id", "cicd.worker.name", "cicd.job.queue_seconds"}
DASHBOARD_UIDS = {"dataops-pipeline-overview", "dataops-jobs-steps", "dataops-traces"}


def _load(path: Path) -> Any:
    return yaml.safe_load(path.read_text())


@pytest.fixture(scope="module")
def compose() -> dict[str, Any]:
    return _load(ROOT / "docker-compose.yml")


@pytest.fixture(scope="module")
def collector() -> dict[str, Any]:
    return _load(OBS / "otel-collector.yaml")


@pytest.fixture(scope="module")
def dashboards() -> dict[str, dict[str, Any]]:
    return {p.name: json.loads(p.read_text()) for p in sorted((OBS / "grafana" / "dashboards").glob("*.json"))}


def test_jaeger_removed(compose: dict[str, Any]) -> None:
    assert "jaeger" not in compose["services"]
    assert not any("jaeger" in v for v in compose.get("volumes", {}))


@pytest.mark.parametrize("service", OBS_SERVICES)
def test_image_pinned(compose: dict[str, Any], service: str) -> None:
    image = compose["services"][service]["image"]
    assert ":" in image, image
    assert not image.endswith(":latest"), image


@pytest.mark.parametrize("service", OBS_SERVICES)
def test_ports_localhost_only(compose: dict[str, Any], service: str) -> None:
    for port in compose["services"][service].get("ports", []):
        assert str(port).startswith("127.0.0.1:"), f"{service}: {port}"


def test_grafana_password_required(compose: dict[str, Any]) -> None:
    env = compose["services"]["grafana"]["environment"]
    value = env["GF_SECURITY_ADMIN_PASSWORD"]
    # ${VAR:?msg} fails compose when unset; no fallback default (and never "admin")
    assert re.fullmatch(r"\$\{GRAFANA_ADMIN_PASSWORD:\?[^}]*\}", value), value


def test_service_list_covers_report_range(compose: dict[str, Any]) -> None:
    # Default 72h hides repos without a recent run from the service/operation dropdowns
    flags = compose["services"]["victoriatraces"]["command"]
    assert "-search.streamFieldsLookbehind=720h" in flags


def test_runner_default_endpoint(compose: dict[str, Any]) -> None:
    runners = [s for s in compose["services"].values() if "OTEL_EXPORTER_OTLP_ENDPOINT" in s.get("environment", {})]
    assert runners
    for svc in runners:
        assert "otel-collector:4317" in svc["environment"]["OTEL_EXPORTER_OTLP_ENDPOINT"]


def test_collector_pipelines(collector: dict[str, Any]) -> None:
    pipelines = collector["service"]["pipelines"]
    assert pipelines["traces"]["processors"][0] == "memory_limiter"
    assert "span_metrics" in pipelines["traces"]["exporters"]
    assert pipelines["metrics"]["receivers"] == ["span_metrics"]
    assert "health_check" in collector["service"]["extensions"]


def test_spanmetrics_dimensions_low_cardinality(collector: dict[str, Any]) -> None:
    dims = {d["name"] for d in collector["connectors"]["span_metrics"]["dimensions"]}
    assert not dims & TRACE_ONLY
    assert {"vcs.repository", "cicd.job", "sf.database", "dcm.target", "cicd.dry_run"} <= dims


def test_spanmetrics_buckets_reach_two_hours(collector: dict[str, Any]) -> None:
    buckets = collector["connectors"]["span_metrics"]["histogram"]["explicit"]["buckets"]
    assert buckets[-1] == "2h"
    assert "30m" in buckets


def test_dashboards_provider_read_only() -> None:
    providers = _load(OBS / "grafana" / "provisioning" / "dashboards" / "dashboards.yaml")["providers"]
    assert providers
    assert all(p["allowUiUpdates"] is False for p in providers)
    assert all(p["folder"] == "DataOps" for p in providers)


def test_datasource_uids() -> None:
    sources = _load(OBS / "grafana" / "provisioning" / "datasources" / "datasources.yaml")["datasources"]
    assert {s["uid"] for s in sources} == {"victoriatraces", "victoriametrics"}


def test_dashboard_uids(dashboards: dict[str, dict[str, Any]]) -> None:
    assert {d["uid"] for d in dashboards.values()} == DASHBOARD_UIDS


def _exprs(node: Any) -> list[str]:
    if isinstance(node, dict):
        found = [node["expr"]] if isinstance(node.get("expr"), str) else []
        return found + [e for v in node.values() for e in _exprs(v)]
    if isinstance(node, list):
        return [e for v in node for e in _exprs(v)]
    return []


def test_dashboard_metric_names(dashboards: dict[str, dict[str, Any]]) -> None:
    exprs = [e for d in dashboards.values() for e in _exprs(d)]
    assert exprs
    names = set(re.findall(r"\b(traces_span_metrics_\w+)", " ".join(exprs)))
    allowed = {
        "traces_span_metrics_calls_total",
        "traces_span_metrics_duration_seconds_bucket",
        "traces_span_metrics_duration_seconds_sum",
        "traces_span_metrics_duration_seconds_count",
    }
    assert names
    assert names <= allowed, names - allowed
    # Trace-only attributes are not metric labels
    for attr in TRACE_ONLY:
        assert attr.replace(".", "_") not in " ".join(exprs)
