# Troubleshooting Guide

Common failures by pipeline job and how to resolve them.

## Job: prepare

| Failure | Cause | Fix |
|---------|-------|-----|
| `Connection default is not configured` | OIDC not set up or SNOW_CONFIG_B64 missing | Check OIDC org claim is configured, or set `USE_OIDC: false` and provide SNOW_CONFIG_B64 secret |
| `Invalid SOURCE_DATABASE` | Input doesn't match `^[A-Z0-9_]+$` | Use UPPERCASE database names only |
| `Invalid SOURCE_SCHEMA` | Input doesn't match `^[A-Za-z0-9_]+$` | Check for special characters in schema name |
| `pre_deploy.sql failed` | Database/schema creation failed | Verify CICD role has CREATE DATABASE privilege |
| `JWT subject not recognized` | OIDC subject mismatch | Run `gh api -X PUT orgs/YOUR_ORG/actions/oidc/customization/sub --input - <<< '{"include_claim_keys":["repository_owner"]}'` |

## Job: scan

| Failure | Cause | Fix |
|---------|-------|-----|
| SonarQube unreachable | Docker stack not running or network issue | Run `./start.sh` to restart; verify `curl http://sonarqube:9000/api/system/status` from runner |
| Quality Gate timeout | SonarQube processing backlog | Increase `timeout-minutes` or wait and re-run |
| SQLFluff threshold exceeded | Critical violations above `SQLFLUFF_FAIL_THRESHOLD` | Fix violations or increase threshold |
| `sonar-scanner: command not found` | Runner image outdated | Rebuild: `./start.sh` |

## Job: deploy

| Failure | Cause | Fix |
|---------|-------|-----|
| `IDENTIFIER not found` | Schema or DCM project doesn't exist | Check `pre_deploy.sql` creates the database, schema, and DCM project |
| DCM plan conflict | Another deploy running to same schema | Wait for concurrency lock (pipeline uses `concurrency:` group) |
| DCM deploy failed after 3 retries | Persistent Snowflake error | Check `snow dcm plan` output; verify object definitions are valid |
| `manifest.yml` parse error | Invalid YAML in consumer repo | Validate with `python3 -c "import yaml; yaml.safe_load(open('manifest.yml'))"` |
| Clone schema creation failed | Insufficient privileges | Verify CICD role has CREATE SCHEMA on the database |

## Job: validate

| Failure | Cause | Fix |
|---------|-------|-----|
| SQL test failures | Schema objects not deployed correctly | Check DCM deploy step output; verify test queries match deployed objects |
| `tests.sqltest` not found | File missing or wrong path | Ensure `sqlunit/tests.sqltest` exists in consumer repo |
| Test timeout | Long-running queries | Optimize test SQL or increase warehouse size |

## Job: cleanup

| Failure | Cause | Fix |
|---------|-------|-----|
| Clone schema not found | Already dropped or never created | Safe to ignore (cleanup is idempotent) |
| Drop schema permission denied | Role lacks DROP privilege | Verify CICD role owns the clone schema |

## Job: release

| Failure | Cause | Fix |
|---------|-------|-----|
| Tag already exists | Duplicate `run_number` (re-run) | GitHub uses `run_number` which increments; if re-running same number, delete the existing tag |
| Zip fails | Disk space or permission issue | Check runner disk space: `df -h` |
| DCM deploy to original fails | Objects conflict with clone residue | Verify cleanup job ran successfully first |

## General Issues

| Failure | Cause | Fix |
|---------|-------|-----|
| `RequestsDependencyWarning: urllib3` | Version mismatch in runner image | Cosmetic warning only, safe to ignore |
| Runner not picking up latest pipeline | GitHub caches workflow ref at trigger time | Trigger again after backbone push is complete |
| Duplicate `uniq_profile_rule_uuids` in SonarQube | Rule setup script running non-idempotently | Rebuild runner image (`./start.sh`) to get fixed `sonar-rules-setup.sh` |
| `id-token: write` permission error | Consumer repo caller missing permissions block | Add `permissions: id-token: write` to the consumer workflow |
