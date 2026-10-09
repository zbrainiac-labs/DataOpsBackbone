#!/bin/bash
set -Eeuo pipefail

SONAR_HOST="${SONAR_HOST:-http://localhost:9000}"
SONAR_AUTH="admin:${SONAR_ADMIN_PASS:-ThisIsNotSecure1234!}"
PROFILE_NAME="md_quality_profile"
TEMPLATE="txt:SimpleRegexMatchCheck"
TEMPLATE_MULTILINE="txt:MultilineTextMatchCheck"

PROFILE_KEY=$(curl -sf -u "$SONAR_AUTH" "$SONAR_HOST/api/qualityprofiles/search?language=txt" \
  | python3 -c "import sys,json; profiles=json.load(sys.stdin)['profiles']; matches=[p['key'] for p in profiles if p['name']=='$PROFILE_NAME']; print(matches[0] if matches else '')")

if [[ -z "$PROFILE_KEY" ]]; then
  echo "Creating quality profile: $PROFILE_NAME"
  PROFILE_KEY=$(curl -sf -u "$SONAR_AUTH" -X POST "$SONAR_HOST/api/qualityprofiles/create" \
    -d "name=$PROFILE_NAME&language=txt" | python3 -c "import sys,json; print(json.load(sys.stdin)['profile']['key'])")
  echo "  Created with key: $PROFILE_KEY"
else
  echo "Profile $PROFILE_NAME exists: $PROFILE_KEY"
fi

echo "Setting $PROFILE_NAME as default..."
curl -s -o /dev/null -u "$SONAR_AUTH" -X POST "$SONAR_HOST/api/qualityprofiles/set_default" \
  -d "qualityProfile=$PROFILE_NAME&language=txt"
echo "  Done"

create_rule() {
  local KEY="$1"
  local NAME="$2"
  local DESC="$3"
  local REGEX="$4"
  local SEVERITY="${5:-MAJOR}"

  EXISTING=$(curl -sf -u "$SONAR_AUTH" "$SONAR_HOST/api/rules/show?key=txt:$KEY" 2>/dev/null | python3 -c "import sys,json; print('exists')" 2>/dev/null || echo "")

  if [[ "$EXISTING" != "exists" ]]; then
    ESCAPED_MSG="${NAME//;/%3B}"
    HTTP_CODE=$(curl -s -o /tmp/sonar_response.json -w "%{http_code}" -u "$SONAR_AUTH" -X POST "$SONAR_HOST/api/rules/create" \
      -d "customKey=$KEY" \
      --data-urlencode "name=$NAME" \
      --data-urlencode "markdownDescription=$DESC" \
      -d "templateKey=$TEMPLATE" \
      -d "severity=$SEVERITY" \
      --data-urlencode "params=expression=$REGEX;message=$ESCAPED_MSG")

    if [ "$HTTP_CODE" -eq 200 ]; then
      echo "  + Created: txt:$KEY"
    else
      MSG=$(python3 -c "import json; print(json.load(open('/tmp/sonar_response.json')).get('errors',[{}])[0].get('msg','unknown'))" 2>/dev/null || echo "HTTP $HTTP_CODE")
      echo "  ! Error:   txt:$KEY ($MSG)"
      return
    fi
  else
    echo "  = Exists:  txt:$KEY"
  fi

  HTTP_CODE=$(curl -s -o /tmp/sonar_activate.json -w "%{http_code}" -u "$SONAR_AUTH" -X POST "$SONAR_HOST/api/qualityprofiles/activate_rule" \
    -d "key=$PROFILE_KEY" \
    -d "rule=txt:$KEY" \
    -d "severity=$SEVERITY" \
    --data-urlencode "params=message=$NAME")

  if [[ "$HTTP_CODE" -eq 200 || "$HTTP_CODE" -eq 204 ]]; then
    echo "    Activated"
  else
    echo "    Already active"
  fi
}

create_multiline_rule() {
  local KEY="$1"
  local NAME="$2"
  local DESC="$3"
  local REGEX="$4"
  local SEVERITY="${5:-MAJOR}"

  EXISTING=$(curl -sf -u "$SONAR_AUTH" "$SONAR_HOST/api/rules/show?key=txt:$KEY" 2>/dev/null | python3 -c "import sys,json; print('exists')" 2>/dev/null || echo "")

  if [[ "$EXISTING" != "exists" ]]; then
    ESCAPED_MSG="${NAME//;/%3B}"
    HTTP_CODE=$(curl -s -o /tmp/sonar_response.json -w "%{http_code}" -u "$SONAR_AUTH" -X POST "$SONAR_HOST/api/rules/create" \
      -d "customKey=$KEY" \
      --data-urlencode "name=$NAME" \
      --data-urlencode "markdownDescription=$DESC" \
      -d "templateKey=$TEMPLATE_MULTILINE" \
      -d "severity=$SEVERITY" \
      --data-urlencode "params=regularExpression=$REGEX;message=$ESCAPED_MSG")

    if [ "$HTTP_CODE" -eq 200 ]; then
      echo "  + Created: txt:$KEY (multiline)"
    else
      MSG=$(python3 -c "import json; print(json.load(open('/tmp/sonar_response.json')).get('errors',[{}])[0].get('msg','unknown'))" 2>/dev/null || echo "HTTP $HTTP_CODE")
      echo "  ! Error:   txt:$KEY ($MSG)"
      return
    fi
  else
    echo "  = Exists:  txt:$KEY (multiline)"
  fi

  HTTP_CODE=$(curl -s -o /tmp/sonar_activate.json -w "%{http_code}" -u "$SONAR_AUTH" -X POST "$SONAR_HOST/api/qualityprofiles/activate_rule" \
    -d "key=$PROFILE_KEY" \
    -d "rule=txt:$KEY" \
    -d "severity=$SEVERITY" \
    --data-urlencode "params=message=$NAME")

  if [[ "$HTTP_CODE" -eq 200 || "$HTTP_CODE" -eq 204 ]]; then
    echo "    Activated"
  else
    echo "    Already active"
  fi
}

create_rule "Disallow_GRANT_Statements_to_PUBLIC" "Disallow GRANT Statements to PUBLIC" "To maintain a secure permissions model, avoid granting to PUBLIC. Assign privileges to specific roles." '(?i)^(?!\s*--).*grant\s+.*\s+to\s+public\b' "CRITICAL"
create_rule "Disallow_GRANT_ALL_PRIVILEGES" "Disallow GRANT ALL PRIVILEGES" "Over-permissioning risk. Always grant specific privileges instead of ALL." '(?i)^(?!\s*--)\s*GRANT\s+ALL\s+(PRIVILEGES\s+)?ON\b' "MAJOR"
create_rule "Disallow_ACCOUNTADMIN_in_scripts" "Disallow ACCOUNTADMIN usage in SQL scripts" "Role escalation risk. Scripts should use least-privilege roles." '(?i)^(?!\s*--)\s*(USE\s+ROLE|SET\s+ROLE|GRANT\s+.*TO\s+ROLE|GRANT\s+ROLE)\s+.*\bACCOUNTADMIN\b' "CRITICAL"
create_rule "Disallow_plaintext_passwords" "Disallow plaintext passwords in DDL" "Security risk. Passwords must not be hardcoded in SQL scripts." "(?i)^(?!\s*--)\s*.*PASSWORD\s*=\s*'[^']+'" "BLOCKER"

echo ""
echo "=== Safety ==="
create_rule "Disallow_CREATE_SCHEMA_without_IF_NOT_EXISTS" "Disallow CREATE SCHEMA without IF NOT EXISTS or REPLACE" "Schema creation without guards risks failure in idempotent deployments." '(?i)^(?!\s*--)\s*CREATE\s+(?!OR\s+REPLACE\b)(?!.*\bIF\s+NOT\s+EXISTS\b).*?\bSCHEMA\b' "MAJOR"
create_rule "Disallow_CREATE_TABLE_without_IF_NOT_EXISTS_or_REPLACE" "Disallow CREATE TABLE without IF NOT EXISTS or REPLACE" "Table creation without guards risks failure in idempotent deployments." '(?is)^(?!\s*--).*CREATE\s+(?!OR\s+REPLACE\b|.*IF\s+NOT\s+EXISTS\b).*TABLE\b' "MAJOR"
create_rule "Disallow_CREATE_statements_with_hardcoded_database_or_schema_prefix" "Disallow CREATE with hardcoded database/schema prefix" "Use relative references for portability across environments." '(?i)^(?!\s*--)\s*create\s+(or\s+replace\s+)?(table|view|schema)\s+(if\s+not\s+exists\s+)?[a-z0-9_]+\.[a-z0-9_]+(\.[a-z0-9_]+)?' "MAJOR"
create_rule "Disallow_dropping_objects_without_IF_EXISTS" "Disallow dropping objects without IF EXISTS" "DROP without IF EXISTS fails if object does not exist." '(?i)^(?!\s*--)\s*DROP\s+(SCHEMA|TABLE|VIEW|DYNAMIC\s+TABLE|STAGE|FILE\s+FORMAT|PROCEDURE|FUNCTION|TASK)\s+(?!IF\s+EXISTS\b)' "MAJOR"
create_rule "Disallow_hardcoded_USE_DATABASE__SCHEMA__or_ROLE_statements" "Disallow hardcoded USE DATABASE, SCHEMA, or ROLE statements" "USE statements hardcode context and break portability." '(?i)^(?!\s*--)\s*USE\s+(DATABASE|SCHEMA|ROLE)\b' "CRITICAL"
create_rule "Disallow_ALTER_TABLE_Drop_Column" "Disallow ALTER TABLE DROP COLUMN (breaking change)" "Dropping columns is destructive and irreversible. Can break downstream views and applications." '(?i)^(?!\s*--)\s*ALTER\s+TABLE\s+.*\bDROP\s+(COLUMN\s+)?' "CRITICAL"
create_rule "Disallow_TRUNCATE_without_safeguard" "Disallow bare TRUNCATE TABLE (data loss risk)" "TRUNCATE permanently removes all data. Flag for review to ensure safeguards exist." '(?i)^(?!\s*--)\s*TRUNCATE\s+(TABLE\s+)?(?:IF\s+EXISTS\s+)?[A-Z0-9_{}\.]+' "CRITICAL"

echo ""
echo "=== Data Type ==="
create_rule "Disallow_usage_of_TIMESTAMP_types_other_than_TIMESTAMP_TZ" "Disallow TIMESTAMP_NTZ and TIMESTAMP_LTZ (only TIMESTAMP_TZ allowed)" "Use TIMESTAMP_TZ for timezone-aware timestamps. TIMESTAMP_NTZ and TIMESTAMP_LTZ cause ambiguity." '^(?!\s*--).*\bTIMESTAMP_(NTZ|LTZ)(\s*\(\s*\d+\s*\))?\b' "MAJOR"

echo ""
echo "=== Data Quality & Consistency ==="
## Disallow_SELECT_star removed — covered by SQLCC:C002 (AST-based SELECT * detection)
create_rule "Disallow_FLOAT_DOUBLE" "Disallow FLOAT/DOUBLE/REAL -- prefer NUMBER(p,s)" "FLOAT has precision issues. Use NUMBER(precision, scale) for deterministic results." '^(?!\s*--).*\b(FLOAT|DOUBLE|REAL)\b' "MAJOR"
create_rule "Disallow_VARCHAR_without_length" "Disallow VARCHAR without explicit length" "Unbounded VARCHAR wastes metadata. Always specify explicit length." "^(?!\\s*--).*(?<!')\\bVARCHAR\\b(?!\\s*\\()" "MINOR"
create_rule "CREATE_TABLE_must_have_COMMENT" "CREATE TABLE must include COMMENT" "Documentation standard. Every table must have a COMMENT." '(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?TABLE\s+(?!.*\bCOMMENT\b).*(?<!\()\s*$' "MINOR"

echo ""
echo "=== Performance & Best Practice ==="
create_rule "Disallow_ORDER_BY_in_views" "Disallow ORDER BY in view definitions" "ORDER BY in views is ignored by consumers and wastes compute." '(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?VIEW\b[\s\S]*?\bORDER\s+BY\b' "MAJOR"
create_rule "Disallow_COPY_INTO_without_ON_ERROR" "Disallow COPY INTO without ON_ERROR clause" "COPY INTO must specify ON_ERROR behavior." '(?i)^(?!\s*--)\s*COPY\s+INTO\s+(?!.*\bON_ERROR\b).*\bFROM\b' "MAJOR"
create_rule "Dynamic_Table_must_have_TARGET_LAG" "Dynamic Tables must specify TARGET_LAG" "Dynamic Tables without TARGET_LAG will fail or use uncontrolled defaults." '(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?DYNAMIC\s+TABLE\s+(?!.*\bTARGET_LAG\b).*\bAS\s+SELECT\b' "MAJOR"
create_rule "Task_must_be_SERVERLESS" "Tasks should use SERVERLESS (no WAREHOUSE clause)" "Tasks should avoid specifying WAREHOUSE to use serverless compute for cost efficiency." '(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?TASK\s+.*WAREHOUSE\s*=' "MAJOR"
create_rule "DEFINE_must_have_COMMENT" "DEFINE TABLE/VIEW/DYNAMIC TABLE must include COMMENT" "All DEFINE statements must include a COMMENT clause for documentation." '(?i)^(?!\s*--)DEFINE\s+(DYNAMIC\s+)?(?:TABLE|VIEW)\s+(?!.*\bCOMMENT\b).*(?:AS\s+SELECT|\))' "MAJOR"

echo ""
echo "=== Naming Convention - Schema ==="
create_rule "Schema_must_have_maturity_prefix" "Schema names must follow DATA_MATURITY_ prefix" "Schema must contain _RAW_, _CUR_, _AGG_, _GOL_, _REF_ or end with _DCM" '(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?SCHEMA\s+(?:IF\s+NOT\s+EXISTS\s+)?(\S+\.)?(?!IF\b)(?!.*_(RAW|CUR|AGG|GOL|REF)_)(?!.*_DCM\b)[A-Z0-9_]+\b' "MAJOR"
create_rule "Schema_must_have_version_suffix" "Schema names must end with _vNNN version" "Schema must end with _v followed by exactly 3 digits (or _DCM for DCM schemas). Lowercase _v is required." '^(?!\s*--)\s*[Cc][Rr][Ee][Aa][Tt][Ee]\s+([Oo][Rr]\s+[Rr][Ee][Pp][Ll][Aa][Cc][Ee]\s+)?[Ss][Cc][Hh][Ee][Mm][Aa]\s+(?:[Ii][Ff]\s+[Nn][Oo][Tt]\s+[Ee][Xx][Ii][Ss][Tt][Ss]\s+)?(\S+\.)?(?![Ii][Ff]\b)[A-Za-z0-9_]+(?<!_DCM)(?<!_v\d\d\d)\b' "MAJOR"

echo ""
echo "=== Naming Convention - Objects ==="
create_rule "Table_name_pattern" "Table names must follow {DOMAIN}+{COMPONENT}_{MAT}_TB_ pattern" "Pattern: {3-char domain}{1-char component}_{RAW|CUR|AGG|GOL}_TB_{name}" '(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?(?!DYNAMIC\s)TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:[A-Z0-9_]+\.){0,2}(?!IF\b)(?![A-Z0-9]{3}[A-Z]_(RAW|CUR|AGG|GOL)_TB_)[A-Z][A-Z0-9_]*' "MAJOR"
create_rule "View_name_pattern" "View names must follow {DOMAIN}+{COMPONENT}_{MAT}_VW_ pattern" "Pattern: {3-char domain}{1-char component}_{RAW|CUR|AGG|GOL}_VW_{name}" '(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?VIEW\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:[A-Z0-9_]+\.){0,2}(?!IF\b)(?![A-Z0-9]{3}[A-Z]_(RAW|CUR|AGG|GOL)_VW_)[A-Z][A-Z0-9_]*' "MAJOR"
create_rule "Dynamic_Table_name_pattern" "Dynamic Table names must follow {DOMAIN}+{COMPONENT}_{MAT}_DT_ pattern" "Pattern: {3-char domain}{1-char component}_{RAW|CUR|AGG|GOL}_DT_{name}" '(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?DYNAMIC\s+TABLE\s+(?:[A-Z0-9_]+\.){0,2}(?!IF\b)(?![A-Z0-9]{3}[A-Z]_(RAW|CUR|AGG|GOL)_DT_)[A-Z][A-Z0-9_]*' "MAJOR"
create_rule "Stage_name_pattern" "Stage names must follow {DOMAIN}+{COMPONENT}_{MAT}_ST_ pattern" "Pattern: {3-char domain}{1-char component}_{RAW|CUR|AGG|GOL}_ST_{name}" '(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?STAGE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:[A-Z0-9_]+\.){0,2}(?!IF\b)(?![A-Z0-9]{3}[A-Z]_(RAW|CUR|AGG|GOL)_ST_)[A-Z][A-Z0-9_]*' "MAJOR"
create_rule "File_Format_name_pattern" "File Format names must follow {DOMAIN}+{COMPONENT}_{MAT}_FF_ pattern" "Pattern: {3-char domain}{1-char component}_{RAW|CUR|AGG|GOL}_FF_{name}" '(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?FILE\s+FORMAT\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:[A-Z0-9_]+\.){0,2}(?!IF\b)(?![A-Z0-9]{3}[A-Z]_(RAW|CUR|AGG|GOL)_FF_)[A-Z][A-Z0-9_]*' "MAJOR"
create_rule "Stored_Procedure_name_pattern" "Stored Procedure names must follow {DOMAIN}+{COMPONENT}_{MAT}_SP_ pattern" "Pattern: {3-char domain}{1-char component}_{RAW|CUR|AGG|GOL}_SP_{name}" '(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?PROCEDURE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:[A-Z0-9_]+\.){0,2}(?!IF\b)(?![A-Z0-9]{3}[A-Z]_(RAW|CUR|AGG|GOL)_SP_)[A-Z][A-Z0-9_]*' "MAJOR"
create_rule "Task_name_pattern" "Task names must follow {DOMAIN}+{COMPONENT}_{MAT}_TK_ pattern" "Pattern: {3-char domain}{1-char component}_{RAW|CUR|AGG|GOL}_TK_{name}" '(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?TASK\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:[A-Z0-9_]+\.){0,2}(?!IF\b)(?![A-Z0-9]{3}[A-Z]_(RAW|CUR|AGG|GOL)_TK_)[A-Z][A-Z0-9_]*' "MAJOR"
create_rule "Stream_name_pattern" "Stream names must follow {DOMAIN}+{COMPONENT}_{MAT}_SM_ pattern" "Pattern: {3-char domain}{1-char component}_{RAW|CUR|AGG|GOL}_SM_{name}" '(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?STREAM\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:[A-Z0-9_]+\.){0,2}(?!IF\b)(?![A-Z0-9]{3}[A-Z]_(RAW|CUR|AGG|GOL)_SM_)[A-Z][A-Z0-9_]*' "MAJOR"
create_rule "Semantic_View_name_pattern" "Semantic View names must follow DOM+COMP_SV_ pattern" "Semantic view names must follow: 4-char domain+component, underscore, SV_, descriptive name." '(?i)^(?!\s*--)\s*CREATE\s+(?:OR\s+REPLACE\s+)?(?:SECURE\s+)?VIEW\s+(?:[A-Z0-9_]+\.){0,2}(?![A-Z0-9]{3}[A-Z]_SV_)[A-Z0-9]{4}_SV_' "MAJOR"
create_rule "Enforce__maturity_level__Code_at_Positions_5_7" "Enforce maturity-level code at positions 5-7" "Object names must have a valid maturity code (RAW, CON, AGG, DAP, DAM) at positions 5-7." '(?i)^(?!\s*--).{4}(RAW|CON|AGG|DAP|DAM)_.*' "CRITICAL"

echo ""
echo "=== Code Style (from SQLFluff gap analysis) ==="
create_rule "Keywords_must_be_UPPER" "SQL keywords must be UPPERCASE" "Enforce consistent UPPER case for SQL keywords (SELECT, FROM, WHERE, JOIN, etc.)." '^(?!\s*--)\s*\b(select|from|where|join|inner|left|right|outer|full|cross|on|and|or|not|group|order|having|limit|union|intersect|except|insert|update|delete|merge|into|values|set|case|when|then|else|end|as|in|is|like|between|exists|distinct|all|any|with|create|alter|drop|grant|revoke|truncate)\b' "MINOR"
create_rule "Unnecessary_ELSE_NULL" "Unnecessary ELSE NULL in CASE statement" "CASE already returns NULL when no ELSE is specified. Remove ELSE NULL for cleaner code." '(?i)^(?!\s*--).*\bELSE\s+NULL\b' "MINOR"
create_rule "JOIN_without_ON_clause" "JOIN without ON clause (potential cartesian join)" "Every JOIN should have an ON clause. Missing ON causes cartesian products." '(?i)^(?!\s*--).*\bJOIN\s+\S+\s*$' "MAJOR"
create_rule "Implicit_alias_missing_AS" "Implicit alias (missing AS keyword)" "Use explicit AS keyword for column and table aliases for readability." '(?i)^(?!\s*--).*\b(SELECT|FROM|JOIN)\s+.*\)\s+[A-Z_][A-Z0-9_]*\s*[,\n]' "MINOR"

echo ""
echo "=== Multiline Rules ==="
create_multiline_rule "DEFINE_must_have_COMMENT_multiline" "DEFINE TABLE/VIEW/DYNAMIC TABLE must include COMMENT (multiline)" "All DEFINE statements for tables, views, and dynamic tables must include a COMMENT clause." '(?ism)^(?!\s*--)DEFINE\s+(DYNAMIC\s+)?(?:TABLE|VIEW)\s+\S+(?:(?!\bCOMMENT\b)(?!\nDEFINE\s)(?!\nCREATE\s).)+?(?=\nDEFINE\s|\nCREATE\s|\Z)' "MAJOR"
create_multiline_rule "Dynamic_Table_must_have_TARGET_LAG_multiline" "Dynamic Tables must specify TARGET_LAG (multiline)" "All DYNAMIC TABLE definitions must include a TARGET_LAG clause." '(?is)(?:^|\n)(?!\s*--)(?:CREATE\s+(?:OR\s+REPLACE\s+)?|DEFINE\s+)DYNAMIC\s+TABLE\s+\S+(?:(?!\bTARGET_LAG\b)(?!(?:CREATE|DEFINE)\s).)+?AS\s+SELECT' "CRITICAL"
create_multiline_rule "Disallow_ORDER_BY_in_views_multiline" "Disallow ORDER BY in view definitions (multiline)" "ORDER BY in views is ignored by consumers and wastes compute." '(?is)(?:^|\n)(?!\s*--)(?:CREATE\s+(?:OR\s+REPLACE\s+)?|DEFINE\s+)VIEW\s+\S+(?:(?!(?:CREATE|DEFINE)\s).)*?\bORDER\s+BY\b' "MAJOR"
create_multiline_rule "Task_must_be_SERVERLESS_multiline" "Tasks should use SERVERLESS - no WAREHOUSE clause (multiline)" "Tasks should avoid specifying WAREHOUSE to use serverless compute." '(?is)(?:^|\n)(?!\s*--)CREATE\s+(?:OR\s+REPLACE\s+)?TASK\s+\S+(?:(?!(?:CREATE|DEFINE)\s).)*?WAREHOUSE\s*=' "MAJOR"
create_multiline_rule "Disallow_COPY_INTO_without_ON_ERROR_multiline" "Disallow COPY INTO without ON_ERROR (multiline)" "COPY INTO must specify ON_ERROR behavior." '(?is)(?:^|\n)(?!\s*--)COPY\s+INTO\s+\S+(?:(?!\bON_ERROR\b)(?!\nCOPY\s)(?!\n(?:CREATE|DEFINE)\s).)+?(?=\nCOPY\s|\n(?:CREATE|DEFINE)\s|$)' "MAJOR"
create_multiline_rule "CREATE_TABLE_must_have_COMMENT_multiline" "CREATE TABLE must include COMMENT (multiline)" "Documentation standard. Every table must have a COMMENT." '(?ism)^(?!\s*--)(?:CREATE\s+(?:OR\s+REPLACE\s+)?|DEFINE\s+)TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?\S+(?:(?!\bCOMMENT\b)(?!\n(?:CREATE|DEFINE)\b).)+?(?=\n(?:CREATE|DEFINE)\b|\Z)' "MINOR"

echo ""
echo "=== Additional Naming ==="
create_rule "Table_names_must_begin_with_a_3_character_alphanumeric_component_code_followed_by_an_underscore" "(dynamic) Table names must begin with a 4-character domain+component code followed by an underscore" "Enforces that CREATE/DEFINE/ALTER TABLE names start with a 4-char domain+component prefix {DOMAIN}{COMP}_." '(?i)^(?!\s*--)(?:\s*(?:create(?:\s+or\s+replace)?|define)|\s*alter)\s+(?:dynamic\s+)?table\s+(?:if\s+not\s+exists\s+)?(?:[A-Z0-9_{}]+\.){0,2}(?!IF\b)(?![A-Z0-9]{4}_)[A-Z][A-Z0-9_]*' "MAJOR"

echo ""
echo "=== Cleanup test rule ==="
curl -s -o /dev/null -u "$SONAR_AUTH" -X POST "$SONAR_HOST/api/rules/delete" -d "key=txt:test_rule_1" 2>/dev/null && echo "Deleted test_rule_1" || true

echo ""
echo "=== Final count ==="
curl -sf -u "$SONAR_AUTH" "$SONAR_HOST/api/qualityprofiles/search?language=txt" | python3 -c "
import sys, json
for p in json.load(sys.stdin)['profiles']:
    if p['key'] == '$PROFILE_KEY':
        print(f\"Profile: {p['name']} | Active rules: {p['activeRuleCount']}\")
"
