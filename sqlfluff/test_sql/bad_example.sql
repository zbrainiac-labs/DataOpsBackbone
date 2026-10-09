-- ============================================================
-- BAD: Non-compliant SQL (should trigger violations)
-- ============================================================

-- DO01: CREATE SCHEMA without IF NOT EXISTS or OR REPLACE
CREATE SCHEMA my_schema;

-- DO02: CREATE TABLE without IF NOT EXISTS or OR REPLACE
CREATE TABLE my_bad_table (id INT);

-- DO03: Hardcoded database/schema prefix
CREATE TABLE my_db.my_schema.bad_table (id INT);

-- DO04: GRANT to PUBLIC
GRANT SELECT ON TABLE foo TO PUBLIC;

-- DO05: DROP without IF EXISTS
DROP TABLE old_data;

-- DO06: USE DATABASE statement
USE DATABASE production_db;
USE SCHEMA public;

-- DO07: TIMESTAMP_NTZ instead of TIMESTAMP_TZ
CREATE OR REPLACE TABLE IF NOT EXISTS IOTI_RAW_TB_BAD_TYPES (
    created_at TIMESTAMP_NTZ,
    updated_at TIMESTAMP_LTZ
) COMMENT = 'Bad timestamp types';

-- DO16: GRANT ALL PRIVILEGES
GRANT ALL PRIVILEGES ON DATABASE foo TO ROLE bar;

-- DO17: ACCOUNTADMIN usage
USE ROLE ACCOUNTADMIN;

-- DO18: Plaintext password
CREATE USER bad_user PASSWORD = 'SuperSecret123';

-- DO19: SELECT *
SELECT * FROM some_table;

-- DO20: FLOAT type
CREATE OR REPLACE TABLE IF NOT EXISTS IOTI_RAW_TB_BAD_FLOAT (
    val FLOAT,
    amt DOUBLE
) COMMENT = 'Bad float types';

-- DO21: VARCHAR without length
CREATE OR REPLACE TABLE IF NOT EXISTS IOTI_RAW_TB_BAD_VARCHAR (
    name VARCHAR,
    desc VARCHAR(100)
) COMMENT = 'Bad varchar';

-- DO22: CREATE TABLE without COMMENT
CREATE OR REPLACE TABLE IOTI_RAW_TB_NO_COMMENT (id NUMBER(10));

-- DO08: Schema name missing maturity prefix (RAW_|CUR_|AGG_|GOL_|REF_)
CREATE SCHEMA IF NOT EXISTS BADSCHEMA_V001;

-- DO09: Schema name missing version suffix (_vNNN)
CREATE SCHEMA IF NOT EXISTS RAW_NO_VERSION;

-- DO10: Table name violates naming pattern
CREATE OR REPLACE TABLE IF NOT EXISTS BAD_TABLE_NAME (id NUMBER(10)) COMMENT = 'bad name';

-- DO11: View name violates naming pattern
CREATE OR REPLACE VIEW BAD_VIEW_NAME AS SELECT 1 AS col;

-- DO12: Dynamic Table name violates naming pattern
CREATE OR REPLACE DYNAMIC TABLE BAD_DT_NAME
    TARGET_LAG = '60 MINUTE'
    WAREHOUSE = MD_TEST_WH
AS SELECT 1 AS col;

-- DO13: Stage name violates naming pattern
CREATE OR REPLACE STAGE BAD_STAGE_NAME;

-- DO14: Cross-database dependency (synthetic marker used by dependency analysis)
-- cross_db_true

-- DO15: Cross-schema dependency (synthetic marker used by dependency analysis)
-- cross_schema_true

-- DO23: ORDER BY in view definition
CREATE OR REPLACE VIEW IOTI_RAW_VW_ORDERED AS SELECT col FROM t ORDER BY col;

-- DO24: COPY INTO without ON_ERROR clause
COPY INTO IOTI_RAW_TB_LANDING FROM @IOTI_RAW_ST_INBOUND;

-- DO25: Dynamic Table without TARGET_LAG
CREATE OR REPLACE DYNAMIC TABLE IOTI_RAW_DT_NO_LAG
    WAREHOUSE = MD_TEST_WH
AS
SELECT 1 AS col;

-- DO26: File Format name violates naming pattern
CREATE OR REPLACE FILE FORMAT BAD_FF_NAME TYPE = CSV;

-- DO27: Stored Procedure name violates naming pattern
CREATE OR REPLACE PROCEDURE BAD_SP_NAME()
RETURNS VARCHAR(100) LANGUAGE SQL AS 'SELECT 1';

-- DO28: Task name violates naming pattern
CREATE OR REPLACE TASK BAD_TASK_NAME
    WAREHOUSE = MD_TEST_WH
    SCHEDULE = 'USING CRON 0 * * * * UTC'
AS SELECT 1;
