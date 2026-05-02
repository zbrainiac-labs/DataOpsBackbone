#!/bin/bash
set -e

SONAR_HOST="${SONAR_HOST:-http://localhost:9000}"
SONAR_AUTH="admin:${SONAR_ADMIN_PASS:-ThisIsNotSecure1234!}"
PROFILE_NAME="md_quality_profile"
TEMPLATE="txt:SimpleRegexMatchCheck"

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

  ENCODED_REGEX=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote('expression=' + sys.argv[1] + '|filePattern=**/*.sql', safe='=|'))" "$REGEX")

  HTTP_CODE=$(curl -s -o /tmp/sonar_response.json -w "%{http_code}" -u "$SONAR_AUTH" -X POST "$SONAR_HOST/api/rules/create" \
    -d "customKey=$KEY" \
    --data-urlencode "name=$NAME" \
    --data-urlencode "markdownDescription=$DESC" \
    -d "templateKey=$TEMPLATE" \
    -d "severity=$SEVERITY" \
    --data-urlencode "params=$ENCODED_REGEX")

  if [ "$HTTP_CODE" -eq 200 ]; then
    echo "  + Created: txt:$KEY"
  else
    MSG=$(python3 -c "import json; print(json.load(open('/tmp/sonar_response.json')).get('errors',[{}])[0].get('msg','unknown'))" 2>/dev/null || echo "HTTP $HTTP_CODE")
    echo "  ~ Exists:  txt:$KEY ($MSG)"
  fi

  curl -s -o /dev/null -u "$SONAR_AUTH" -X POST "$SONAR_HOST/api/qualityprofiles/activate_rule" \
    -d "key=$PROFILE_KEY" \
    -d "rule=txt:$KEY" \
    -d "severity=$SEVERITY" 2>/dev/null && echo "    Activated" || echo "    Activation skipped"
}

echo "=== Security & Access Control ==="
create_rule "Disallow_GRANT_ALL_PRIVILEGES" "Disallow GRANT ALL PRIVILEGES" "Over-permissioning risk. Always grant specific privileges instead of ALL." '(?i)^(?!\s*--)\s*GRANT\s+ALL\s+(PRIVILEGES\s+)?ON\b' "MAJOR"
create_rule "Disallow_ACCOUNTADMIN_in_scripts" "Disallow ACCOUNTADMIN usage in SQL scripts" "Role escalation risk. Scripts should use least-privilege roles." '(?i)^(?!\s*--)\s*(USE\s+ROLE|SET\s+ROLE|GRANT\s+.*TO\s+ROLE|GRANT\s+ROLE)\s+.*\bACCOUNTADMIN\b' "CRITICAL"
create_rule "Disallow_plaintext_passwords" "Disallow plaintext passwords in DDL" "Security risk. Passwords must not be hardcoded in SQL scripts." "(?i)^(?!\s*--)\s*.*PASSWORD\s*=\s*'[^']+'" "BLOCKER"

echo ""
echo "=== Data Type ==="
create_rule "Disallow_usage_of_TIMESTAMP_types_other_than_TIMESTAMP_TZ" "Disallow TIMESTAMP_NTZ and TIMESTAMP_LTZ (only TIMESTAMP_TZ allowed)" "Use TIMESTAMP_TZ for timezone-aware timestamps. TIMESTAMP_NTZ and TIMESTAMP_LTZ cause ambiguity." '^(?!\s*--).*\bTIMESTAMP_(NTZ|LTZ)(\s*\(\s*\d+\s*\))?\b' "MAJOR"

echo ""
echo "=== Data Quality & Consistency ==="
create_rule "Disallow_SELECT_star" "Disallow SELECT * (force explicit column lists)" "Explicit column lists prevent breakage when schema changes." '(?i)^(?!\s*--)\s*SELECT\s+\*\s+FROM\b' "MINOR"
create_rule "Disallow_FLOAT_DOUBLE" "Disallow FLOAT/DOUBLE/REAL -- prefer NUMBER(p,s)" "FLOAT has precision issues. Use NUMBER(precision, scale) for deterministic results." '^(?!\s*--).*\b(FLOAT|DOUBLE|REAL)\b' "MAJOR"
create_rule "Disallow_VARCHAR_without_length" "Disallow VARCHAR without explicit length" "Unbounded VARCHAR wastes metadata. Always specify explicit length." '^(?!\s*--).*\bVARCHAR\s*[^(]' "MINOR"
create_rule "CREATE_TABLE_must_have_COMMENT" "CREATE TABLE must include COMMENT" "Documentation standard. Every table must have a COMMENT." '(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?TABLE\s+(?!.*\bCOMMENT\b).*;\s*$' "MINOR"

echo ""
echo "=== Performance & Best Practice ==="
create_rule "Disallow_ORDER_BY_in_views" "Disallow ORDER BY in view definitions" "ORDER BY in views is ignored by consumers and wastes compute." '(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?VIEW\b[\s\S]*?\bORDER\s+BY\b' "MAJOR"
create_rule "Disallow_COPY_INTO_without_ON_ERROR" "Disallow COPY INTO without ON_ERROR clause" "COPY INTO must specify ON_ERROR behavior." '(?i)^(?!\s*--)\s*COPY\s+INTO\s+(?!.*\bON_ERROR\b).*;\s*$' "MAJOR"
create_rule "Dynamic_Table_must_have_TARGET_LAG" "Dynamic Tables must specify TARGET_LAG" "Dynamic Tables without TARGET_LAG will fail or use uncontrolled defaults." '(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?DYNAMIC\s+TABLE\s+(?!.*\bTARGET_LAG\b)' "MAJOR"

echo ""
echo "=== Naming Convention - Schema ==="
create_rule "Schema_must_have_maturity_prefix" "Schema names must follow DOMAIN_MATURITY_ prefix" "Schema must start with RAW_, CUR_, AGG_, GOL_, or REF_" '(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?SCHEMA\s+(IF\s+NOT\s+EXISTS\s+)?(?:[a-z0-9_]+\.)?(?!RAW_|CUR_|AGG_|GOL_|REF_)[a-z0-9_]+;' "MAJOR"
create_rule "Schema_must_have_version_suffix" "Schema names must end with _vNNN version" "Schema must end with _v followed by exactly 3 digits." '(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?SCHEMA\s+(IF\s+NOT\s+EXISTS\s+)?(?:[a-z0-9_]+\.)?[a-z0-9_]+(?<!_v\d{3});' "MAJOR"

echo ""
echo "=== Naming Convention - Objects ==="
create_rule "Table_name_pattern" "Table names must follow DOM+COMP_MAT_TB_ pattern" "Pattern: {3-char domain}{1-char component}_{RAW|CUR|AGG|GOL}_TB_{name}" '(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?(?!DYNAMIC\s)TABLE\s+(IF\s+NOT\s+EXISTS\s+)?(?:[A-Z0-9_]+\.){0,2}(?![A-Z0-9]{3}[A-Z]_(RAW|CUR|AGG|GOL)_TB_)[A-Z_][A-Z0-9_]*' "MAJOR"
create_rule "View_name_pattern" "View names must follow DOM+COMP_MAT_VW_ pattern" "Pattern: {3-char domain}{1-char component}_{RAW|CUR|AGG|GOL}_VW_{name}" '(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?VIEW\s+(?:[A-Z0-9_]+\.){0,2}(?![A-Z0-9]{3}[A-Z]_(RAW|CUR|AGG|GOL)_VW_)[A-Z_][A-Z0-9_]*' "MAJOR"
create_rule "Dynamic_Table_name_pattern" "Dynamic Table names must follow DOM+COMP_MAT_DT_ pattern" "Pattern: {3-char domain}{1-char component}_{RAW|CUR|AGG|GOL}_DT_{name}" '(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?DYNAMIC\s+TABLE\s+(?:[A-Z0-9_]+\.){0,2}(?![A-Z0-9]{3}[A-Z]_(RAW|CUR|AGG|GOL)_DT_)[A-Z_][A-Z0-9_]*' "MAJOR"
create_rule "Stage_name_pattern" "Stage names must follow DOM+COMP_MAT_ST_ pattern" "Pattern: {3-char domain}{1-char component}_{RAW|CUR|AGG|GOL}_ST_{name}" '(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?STAGE\s+(?:[A-Z0-9_]+\.){0,2}(?![A-Z0-9]{3}[A-Z]_(RAW|CUR|AGG|GOL)_ST_)[A-Z_][A-Z0-9_]*' "MAJOR"
create_rule "File_Format_name_pattern" "File Format names must follow DOM+COMP_MAT_FF_ pattern" "Pattern: {3-char domain}{1-char component}_{RAW|CUR|AGG|GOL}_FF_{name}" '(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?FILE\s+FORMAT\s+(?:[A-Z0-9_]+\.){0,2}(?![A-Z0-9]{3}[A-Z]_(RAW|CUR|AGG|GOL)_FF_)[A-Z_][A-Z0-9_]*' "MAJOR"
create_rule "Stored_Procedure_name_pattern" "Stored Procedure names must follow DOM+COMP_MAT_SP_ pattern" "Pattern: {3-char domain}{1-char component}_{RAW|CUR|AGG|GOL}_SP_{name}" '(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?PROCEDURE\s+(?:[A-Z0-9_]+\.){0,2}(?![A-Z0-9]{3}[A-Z]_(RAW|CUR|AGG|GOL)_SP_)[A-Z_][A-Z0-9_]*' "MAJOR"
create_rule "Task_name_pattern" "Task names must follow DOM+COMP_MAT_TK_ pattern" "Pattern: {3-char domain}{1-char component}_{RAW|CUR|AGG|GOL}_TK_{name}" '(?i)^(?!\s*--)\s*CREATE\s+(OR\s+REPLACE\s+)?TASK\s+(?:[A-Z0-9_]+\.){0,2}(?![A-Z0-9]{3}[A-Z]_(RAW|CUR|AGG|GOL)_TK_)[A-Z_][A-Z0-9_]*' "MAJOR"

echo ""
echo "=== Code Style (from SQLFluff gap analysis) ==="
create_rule "Keywords_must_be_UPPER" "SQL keywords must be UPPERCASE" "Enforce consistent UPPER case for SQL keywords (SELECT, FROM, WHERE, JOIN, etc.)." '^\s*\b(select|from|where|join|inner|left|right|outer|full|cross|on|and|or|not|group|order|having|limit|union|intersect|except|insert|update|delete|merge|into|values|set|case|when|then|else|end|as|in|is|like|between|exists|distinct|all|any|with|create|alter|drop|grant|revoke|truncate)\b' "MINOR"
create_rule "Unnecessary_ELSE_NULL" "Unnecessary ELSE NULL in CASE statement" "CASE already returns NULL when no ELSE is specified. Remove ELSE NULL for cleaner code." '(?i)\bELSE\s+NULL\b' "MINOR"
create_rule "JOIN_without_ON_clause" "JOIN without ON clause (potential cartesian join)" "Every JOIN should have an ON clause. Missing ON causes cartesian products." '(?i)\bJOIN\s+\S+\s*$' "MAJOR"
create_rule "Implicit_alias_missing_AS" "Implicit alias (missing AS keyword)" "Use explicit AS keyword for column and table aliases for readability." '(?i)\b(SELECT|FROM|JOIN)\s+.*\)\s+[A-Z_][A-Z0-9_]*\s*[,\n]' "MINOR"

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
