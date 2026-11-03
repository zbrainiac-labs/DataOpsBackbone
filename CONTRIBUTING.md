# Contributing to DataOpsBackbone

## Prerequisites

- Docker Desktop (for the full stack)
- Python 3.14 (same as the runner image; 3.10+ works for the tools)
- Snowflake CLI (`snow`) >= 3.18.0
- A Snowflake account with a `CICD` role configured

## Local Development Setup

```bash
# Clone the repo
git clone https://github.com/zbrainiac-labs/DataOpsBackbone.git
cd DataOpsBackbone

# Install Python dev tools
pip install ruff mypy pytest sqlfluff pyyaml regex types-regex

# Create .env with your credentials (see "Configure .env" in README.md):
# GitHub org/token, Postgres + SonarQube passwords, SNOW_ACCOUNT, SNOW_USER, SNOW_PAT

# Build the images locally and start the stack (SonarQube, runners, Jaeger, nginx)
./start.sh                      # add --no-observability to skip Jaeger
```

## Running Tests

```bash
# Python unit tests
pytest tests/ -v

# Lint Python code
ruff check .
ruff format --check .

# Type check
mypy sqlfluff/ github-runner/*.py

# Shell lint
shellcheck github-runner/*.sh start.sh local-ci/*.sh

# SQLFluff lint (standalone, against test fixtures)
cd sqlfluff && python3 lint.py test_sql/good_example.sql

# SonarQube self-scan with the stack's SonarQube (same gate as CI)
bash local-ci/sonar-self-scan.sh

# Full pipeline locally with act (requires running stack + Snowflake credentials)
local-ci/run.sh --project=../project-one --full
```

## Project Layout

| Directory | Contents |
|-----------|----------|
| `github-runner/` | All helper scripts, Dockerfile, Python converters |
| `sqlfluff/` | Standalone linter with 28 custom regex rules (DO01-DO28) |
| `sqlfluff/plugins/dataops_rules/` | Custom rule definitions |
| `.github/workflows/` | Reusable pipeline (`dataops-pipeline.yml`) + CI and image publishing (`ci.yml`) |
| `.github/actions/snowflake-connect/` | Composite action for Snowflake auth |
| `sonarqube/` | Custom SonarQube image with SQL + Text plugins |
| `local-ci/` | `run.sh` (pipeline via act) and `sonar-self-scan.sh` (SonarQube gate) |
| `jaeger/` | Jaeger v2 config for pipeline tracing |
| `tests/` | Pytest test suite for Python utilities |

## Making Changes

1. Create a feature branch from `main`
2. Make your changes
3. Run the full test suite (see above)
4. If modifying shell scripts, ensure `set -Eeuo pipefail` (or `set +e` with `set -u` for scripts that capture exit codes)
5. If modifying Python, ensure type hints are present and `ruff` + `mypy` pass
6. Submit a PR -- `ci.yml` runs lint, tests, Trivy and the SonarQube gate. Docker images are published only from `main` or a `v*` tag, after all checks pass.

## Rule Development

SQL linting rules live in two places with **no overlap**:

- **SonarQube** (`sonar-rules-setup.sh`): 40 regex rules created via REST API at runner startup
- **SQLFluff plugin** (`sqlfluff/plugins/dataops_rules/__init__.py`): 28 regex rules (DO01-DO28)

See `RULES.md` for the complete mapping.

When adding a new rule:
1. Choose the right tool (SonarQube for CI-only, SQLFluff plugin for local + CI)
2. Add the rule definition
3. Add a violation example to `sqlfluff/test_sql/bad_example.sql`
4. Add a compliant example to `sqlfluff/test_sql/good_example.sql`
5. Add a test case in `tests/test_lint_custom_rules.py`
