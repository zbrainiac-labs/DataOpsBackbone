# Open Points

## Priority 2 - Planned

### Database Clone for Regression Tests
- Clone reference database per build, update manifest with build-id, deploy and run SQL tests against clone
- Currently commented out in `sql_validation_v4.sh` (clone scripts exist: `snowflake-clone-db_v2.sh`, `snowflake-drop-clone-db_v2.sh`)
- Re-enable when regression test suite is mature
- GitHub Issue: [#2](https://github.com/zbrainiac-labs/DataOpsBackbone/issues/2)

### SonarQube "no lines of code" Warning
- SQL Code Checker plugin doesn't produce `ncloc` metrics, causing "main branch has no lines of code" dashboard warning
- Cosmetic only — issues are still detected and reported correctly
- Requires upstream fix in the SQL Code Checker community plugin

## Priority 3 - Deferred

### SonarQube Test Execution Reports
- Surface SQL test results (CTRF JSON) in SonarQube via `sonar.testExecutionReportPaths`
- Requires converting CTRF JSON to SonarQube Generic Test Execution format (XML only)
- GitHub Issue: [#3](https://github.com/zbrainiac-labs/DataOpsBackbone/issues/3)

### Quality Gate Enforcement
- Currently `QUALITY_GATE_ENFORCED: false` across all consumer repos
- Enable per-repo once teams are comfortable with the rule set
- GitHub Issue: [#4](https://github.com/zbrainiac-labs/DataOpsBackbone/issues/4)
