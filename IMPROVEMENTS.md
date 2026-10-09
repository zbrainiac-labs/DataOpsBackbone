# DataOpsBackbone -- Improvement Plan

## Context

End-to-end review of the DataOpsBackbone project -- a reusable DataOps CI/CD framework for Snowflake combining GitHub Actions, SonarQube, SQLFluff, and Snowflake DCM into a 6-job pipeline (`prepare -> scan -> deploy -> validate -> cleanup -> release`).

**Key strengths:**
- OIDC-first authentication with PAT fallback
- 82 SQL linting rules across SonarQube + SQLFluff with no overlap
- Good `.gitignore` coverage -- no secrets committed
- Docker Compose with YAML anchors for DRY runner config

**Key gaps:**
- Zero automated tests for Python code
- No Python linting/formatting tooling
- Snowflake connection setup duplicated 6x in the workflow
- Silent error swallowing in Python code
- Inconsistent shell strictness (`set -e` vs `set -Eeuo pipefail`)
- Hardcoded local paths and account identifiers

---

## Improvements

Priority: P1 = critical, P2 = high, P3 = medium, P4 = low.

### Testing

| ID | Description | Prio | Status |
|----|-------------|------|--------|
| IMP-01 | **Add unit tests for Python utilities.** None of the 6 Python files have tests. `ddl_uppercase_keywords.py`, `sqlfluff_to_sonar.py`, `ctrf_to_sonar_test.py`, `convert_junit_to_ctrf.py`, and `lint.py` all transform data and are highly testable. Add a `tests/` directory with pytest. | P1 | DONE |
| IMP-02 | **Add integration tests for shell scripts.** The shell scripts (`render-sql_v1.sh`, `sql_validation_v4.sh`, `snowflake-deploy-dcm_v1.sh`) are the pipeline backbone but have no automated tests. Use bats-core or shellcheck-based smoke tests with mocked `snow` CLI calls. | P2 | DONE |
| IMP-03 | **Rename `ctrf_to_sonar_test.py` to `ctrf_to_sonar_converter.py`.** The `_test` suffix is misleading -- it is a converter, not a test. Any future test runner will incorrectly pick it up as a test file. | P1 | DONE |

### Code Quality -- Python

| ID | Description | Prio | Status |
|----|-------------|------|--------|
| IMP-04 | **Add Python linting and formatting toolchain.** No `ruff`, `black`, `flake8`, `pylint`, or `mypy` configured. Add a `pyproject.toml` with `ruff` (linting + formatting) and `mypy` (type checking) as minimal baseline. | P1 | DONE |
| IMP-05 | **Add type hints to all Python functions.** Only 1 of ~12 functions has type annotations. Add parameter and return types to all public functions, especially the converter utilities. | P2 | DONE |
| IMP-06 | **Fix silent error swallowing in `sqlfluff/lint.py`.** Lines 38-52 catch `json.JSONDecodeError` and `TypeError` with `pass`, silently dropping unparseable SQLFluff violations. At minimum, log a warning so users know violations were lost. | P1 | DONE |
| IMP-07 | **Replace `sys.path.insert` hack in `lint.py`.** Line 22 uses `sys.path.insert(0, ...)` for plugin imports. Refactor to a proper Python package with `pyproject.toml` entry points or use relative imports. | P3 | DONE |
| IMP-08 | **Add argument validation to `sqlfluff_to_sonar.py`.** Reading `sys.argv[1]` and `sys.argv[2]` at module level without validation produces a cryptic `IndexError` on missing args. Use `argparse` or at least a guard with a usage message. | P2 | DONE |
| IMP-09 | **Refactor `ddl_uppercase_keywords.py` for testability.** It reads from `sys.stdin` at module level, making it impossible to unit-test without stdin mocking. Extract logic into functions that accept strings, with a `__main__` guard for the CLI entry point. | P2 | DONE |

### Code Quality -- Shell

| ID | Description | Prio | Status |
|----|-------------|------|--------|
| IMP-10 | **Standardize shell strict mode across all scripts.** 5 scripts use only `set -e`, while the workflow uses `set -Eeuo pipefail`. Standardize all 18 scripts to `set -Eeuo pipefail` so pipe failures and unset variables are caught. | P1 | DONE |
| IMP-11 | **Add ShellCheck CI step.** No shell linting exists. Add a `shellcheck` step to the pipeline (or a pre-commit hook) for all `.sh` files in `github-runner/`. | P2 | DONE |
| IMP-12 | **Add structured logging to shell scripts.** All scripts use raw `echo` with no log levels. Introduce a shared `log()` function with levels (INFO, WARN, ERROR) and timestamps. | P3 | OPEN |

### CI/CD Pipeline

| ID | Description | Prio | Status |
|----|-------------|------|--------|
| IMP-13 | **Deduplicate Snowflake connection setup in `dataops-pipeline.yml`.** The identical ~20-line setup block is copy-pasted across all 6 jobs (~120 lines of duplication). Extract into a GitHub composite action under `.github/actions/snowflake-connect/action.yml`. | P1 | DONE |
| IMP-14 | **Add a self-test workflow for this repo.** The backbone repo itself has no CI. Add a workflow that runs pytest, shellcheck, ruff, and the SQLFluff linter against `sqlfluff/test_sql/` on push/PR to `main`. | P1 | DONE |
| IMP-15 | **Pin Docker base images to digests.** `github-runner/Dockerfile` uses `eclipse-temurin:21-jdk-noble` and `sonarqube/Dockerfile` uses tag-based references. Pin to SHA256 digests or specific patch versions for reproducible builds. | P2 | DONE |
| IMP-16 | **Add Dependabot or Renovate for dependency updates.** No automated dependency update mechanism. Add `.github/dependabot.yml` covering `github-actions`, `docker`, and `pip` ecosystems. | P2 | DONE |

### Security

| ID | Description | Prio | Status |
|----|-------------|------|--------|
| IMP-17 | **Remove hardcoded Snowflake account identifier.** `dataops-pipeline.yml:68` defaults to `zs28104.eu-central-1`. This ties the reusable workflow to a specific account. Make it required with no default, or document it as the demo/reference value. | P2 | DONE |
| IMP-18 | **Remove hardcoded local path in `dataops-pipeline.sh`.** Line 27 has `BASE_WORKSPACE:-/Users/mdaeppen/workspace`. Use `$(git rev-parse --show-toplevel)` or `$(pwd)` instead. | P2 | DONE |
| IMP-19 | **Add CODEOWNERS file.** No `CODEOWNERS` exists. Add one to enforce review requirements for critical files (workflow YAMLs, Dockerfiles, security-sensitive scripts). | P3 | DONE |

### Documentation

| ID | Description | Prio | Status |
|----|-------------|------|--------|
| IMP-20 | **Add CONTRIBUTING.md with developer setup guide.** The README covers consumer repo usage well but lacks guidance for contributors to this backbone repo (how to run locally, test changes, submit PRs). | P3 | DONE |
| IMP-21 | **Document the rule ID mapping between SonarQube and SQLFluff.** Rules DO01-DO28 are defined in both `sonar-rules-setup.sh` and `sqlfluff/plugins/dataops_rules/__init__.py` with deliberate non-overlap. Add a rules reference table. | P3 | DONE |
| IMP-22 | **Add architecture diagram to README.** A visual diagram showing: consumer repo -> workflow_call -> 6-job pipeline -> SonarQube / Snowflake DCM / CTRF would aid onboarding. | P4 | DONE |

### Maintainability

| ID | Description | Prio | Status |
|----|-------------|------|--------|
| IMP-23 | **Clean up legacy/duplicate scripts.** Both v2 and v3 versions exist for clone/drop scripts. If v2 is superseded, remove or deprecate. `snowflake-deploy-structure_v2.sh` is labeled "legacy" in the README. | P2 | DONE |
| IMP-24 | **Add `.editorconfig` for consistent formatting.** No editor configuration exists. Enforce indent style, size, EOL, and trailing whitespace across file types. | P4 | DONE |
| IMP-25 | **Move SonarQube backup XMLs out of the repo.** The `backup/` directory contains 38 XML quality profile exports that add noise. Consider storing them as GitHub Release artifacts. | P4 | DONE |

---

## Priority Summary

| Priority | Count | Done | Items |
|----------|-------|------|-------|
| P1 -- Critical | 7 | 7 DONE | IMP-01, IMP-03, IMP-04, IMP-06, IMP-10, IMP-13, IMP-14 |
| P2 -- High | 10 | 10 DONE | IMP-02, IMP-05, IMP-08, IMP-09, IMP-11, IMP-15, IMP-16, IMP-17, IMP-18, IMP-23 |
| P3 -- Medium | 5 | 4 DONE | IMP-07, IMP-12, IMP-19, IMP-20, IMP-21 |
| P4 -- Low | 3 | 3 DONE | IMP-22, IMP-24, IMP-25 |

---

## Suggested Execution Order

1. **Quick wins (IMP-03, IMP-06, IMP-10, IMP-18):** Rename misleading file, fix silent error swallowing, standardize shell strict mode, remove hardcoded path
2. **Toolchain setup (IMP-04, IMP-14, IMP-11):** Add ruff/mypy config, self-test CI workflow, shellcheck
3. **Pipeline DRY (IMP-13):** Extract Snowflake connection composite action
4. **Testing (IMP-01, IMP-09, IMP-08):** Refactor Python for testability, add pytest suite
5. **Housekeeping (IMP-23, IMP-05, IMP-15, IMP-16, IMP-17):** Remove legacy scripts, add type hints, pin images, add Dependabot

---

## Execution Log (P1 + P2)

All P1 and P2 items have been implemented. Here is what was done:

| Step | IMP IDs | What changed |
|------|---------|-------------|
| 1 | IMP-03 | Renamed `ctrf_to_sonar_test.py` to `ctrf_to_sonar_converter.py`, updated `dataops-pipeline.yml` and `README.md` refs |
| 2 | IMP-06 | Replaced silent `except ... pass` with `stderr` warning in `sqlfluff/lint.py` |
| 3 | IMP-10 | Upgraded 7 scripts to `set -Eeuo pipefail`, added `set -u` with `:-` guards to 6 `set +e` scripts, added strict mode to 1 bare script |
| 4 | IMP-17, IMP-18 | Removed hardcoded path in `dataops-pipeline.sh`, removed `SNOWFLAKE_ACCOUNT` default, added OIDC validation guard, updated README |
| 5 | IMP-04 | Created `pyproject.toml` with ruff + mypy config |
| 6 | IMP-08, IMP-09 | Refactored `sqlfluff_to_sonar.py` into `convert()` + `main()` functions, refactored `ddl_uppercase_keywords.py` with `process_line()`/`process_lines()` + `__main__` guard |
| 7 | IMP-13 | Created `.github/actions/snowflake-connect/action.yml` composite action, replaced 6 duplicated blocks (~120 lines removed) |
| 8 | IMP-05 | Added type hints to all ~15 functions across 6 Python files, tightened mypy to `disallow_untyped_defs = true` |
| 9 | IMP-01, IMP-11, IMP-14 | Created `tests/` with 4 pytest test files + conftest, created `.github/workflows/ci.yml` with ruff + mypy + pytest + shellcheck |
| 10 | IMP-15, IMP-16, IMP-23 | Pinned Docker base images, created `.github/dependabot.yml`, deleted 3 legacy v2 scripts |
| 11 | E2E | Created `github-runner/e2e-test.sh` -- full pipeline simulation (build, stack up, deps + DCM + validation against live Snowflake, teardown) |

### New files created

- `pyproject.toml` -- ruff + mypy config
- `.github/actions/snowflake-connect/action.yml` -- composite action
- `.github/workflows/ci.yml` -- self-test CI workflow
- `.github/dependabot.yml` -- automated dependency updates
- `tests/conftest.py`, `tests/__init__.py` -- pytest fixtures
- `tests/test_ddl_uppercase_keywords.py` -- DDL processor tests
- `tests/test_ctrf_to_sonar_converter.py` -- CTRF converter tests
- `tests/test_sqlfluff_to_sonar.py` -- SQLFluff-to-SonarQube converter tests
- `tests/test_lint_custom_rules.py` -- custom regex rule tests
- `github-runner/e2e-test.sh` -- E2E Docker test script

### Files deleted

- `github-runner/ctrf_to_sonar_test.py` (renamed to `ctrf_to_sonar_converter.py`)
- `github-runner/snowflake-clone-db_v2.sh` (legacy)
- `github-runner/snowflake-drop-clone-db_v2.sh` (legacy)
- `github-runner/snowflake-deploy-structure_v2.sh` (legacy)
