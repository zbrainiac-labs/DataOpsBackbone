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

-- DO25: Dynamic Table without TARGET_LAG
CREATE OR REPLACE DYNAMIC TABLE IOTI_RAW_DT_NO_LAG
    WAREHOUSE = MD_TEST_WH
AS
SELECT 1 AS col;
