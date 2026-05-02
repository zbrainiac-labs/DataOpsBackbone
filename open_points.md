# Open Points

## Priority 2 - Planned

### Database Clone for Regression Tests
- Clone reference database per build, update manifest with build-id, deploy and run SQL tests against clone
- Currently commented out in `sql_validation_v4.sh` (clone scripts exist: `snowflake-clone-db_v2.sh`, `snowflake-drop-clone-db_v2.sh`)
- Re-enable when regression test suite is mature
- GitHub Issue: [#2](https://github.com/zbrainiac-labs/DataOpsBackbone/issues/2)

## Priority 3 - Deferred

### SonarQube External Issues Integration
- Surface SQL test failures as code issues on SonarQube dashboard via `sonar.externalIssuesReportPaths`
- Requires converting CTRF JSON test failures to SonarQube Generic Issue Import format
- GitHub Issue: [#3](https://github.com/zbrainiac-labs/DataOpsBackbone/issues/3)

### Quality Gate Enforcement
- Currently `QUALITY_GATE_ENFORCED: false` across all consumer repos
- Enable per-repo once teams are comfortable with the rule set
- GitHub Issue: [#4](https://github.com/zbrainiac-labs/DataOpsBackbone/issues/4)
