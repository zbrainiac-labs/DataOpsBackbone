USE ROLE ACCOUNTADMIN;
DROP DATABASE IF EXISTS DATAOPS;
CREATE DATABASE IF NOT EXISTS DATAOPS;
USE DATABASE DATAOPS;

DROP SCHEMA IF EXISTS IOT_RAW_v001;
CREATE SCHEMA IF NOT EXISTS IOT_RAW_v001;

DROP SCHEMA IF EXISTS IOT_AGG_v001;
CREATE SCHEMA IF NOT EXISTS IOT_AGG_v001;

DROP SCHEMA IF EXISTS IOT_DAP_v001;
CREATE SCHEMA IF NOT EXISTS IOT_DAP_v001;

DROP SCHEMA IF EXISTS REF_RAW_v001;
CREATE SCHEMA IF NOT EXISTS REF_RAW_v001;

CREATE ROLE IF NOT EXISTS CICD;

-- Database level grants
GRANT USAGE ON DATABASE DATAOPS TO ROLE CICD;
GRANT CREATE SCHEMA ON DATABASE DATAOPS TO ROLE CICD;
GRANT USAGE ON WAREHOUSE MD_TEST_WH TO ROLE CICD;
GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE CICD;
GRANT MANAGE WAREHOUSES ON ACCOUNT TO ROLE CICD;
GRANT CREATE SHARE ON ACCOUNT TO ROLE CICD;
GRANT CREATE LISTING ON ACCOUNT TO ROLE CICD;

-- Schema-level privileges
GRANT ALL PRIVILEGES ON SCHEMA DATAOPS.IOT_RAW_v001 TO ROLE CICD;
GRANT ALL PRIVILEGES ON SCHEMA DATAOPS.IOT_AGG_v001 TO ROLE CICD;
GRANT ALL PRIVILEGES ON SCHEMA DATAOPS.IOT_DAP_v001 TO ROLE CICD;
GRANT ALL PRIVILEGES ON SCHEMA DATAOPS.REF_RAW_v001 TO ROLE CICD;

-- Future grants
GRANT ALL PRIVILEGES ON FUTURE SCHEMAS IN DATABASE DATAOPS TO ROLE CICD;
GRANT SELECT, INSERT, UPDATE, DELETE ON FUTURE TABLES IN SCHEMA DATAOPS.IOT_RAW_v001 TO ROLE CICD;
GRANT SELECT, INSERT, UPDATE, DELETE ON FUTURE TABLES IN SCHEMA DATAOPS.IOT_AGG_v001 TO ROLE CICD;
GRANT SELECT, INSERT, UPDATE, DELETE ON FUTURE TABLES IN SCHEMA DATAOPS.IOT_DAP_v001 TO ROLE CICD;
GRANT SELECT, INSERT, UPDATE, DELETE ON FUTURE TABLES IN SCHEMA DATAOPS.REF_RAW_v001 TO ROLE CICD;

-- SNOWFLAKE access
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE CICD;
--GRANT CREATE ORGANIZATION LISTING IN
-- TODO -- GRANT CREATE ORGANIZATION LISTING TO ROLE CICD;

-- Create Resource Monitor for Budget Control (100 credits/month)
CREATE OR REPLACE RESOURCE MONITOR finops_budget_monitor
WITH
    CREDIT_QUOTA = 100,                  -- Monthly limit of 100 credits
    FREQUENCY = 'MONTHLY',               -- Reset quota monthly
    START_TIMESTAMP = IMMEDIATELY
    TRIGGERS 
        ON 75 PERCENT DO NOTIFY          -- Notify at 75% usage
        ON 90 PERCENT DO SUSPEND         -- Suspend warehouse at 90% usage
        ON 100 PERCENT DO SUSPEND_IMMEDIATE; -- Immediately suspend at 100% usage

-- User setup
GRANT ROLE CICD TO USER SVC_CICD;
USE ROLE CICD;


USE SCHEMA IOT_RAW_v001;

-- Create the target table if needed
CREATE OR REPLACE TABLE IOT_RAW (
    SENSOR_ID INT,
    SENSOR_0 FLOAT,
    SENSOR_1 FLOAT,
    SENSOR_2 FLOAT,
    SENSOR_3 FLOAT,
    SENSOR_4 FLOAT,
    SENSOR_5 FLOAT,
    SENSOR_6 FLOAT,
    SENSOR_7 FLOAT,
    SENSOR_8 FLOAT,
    SENSOR_9 FLOAT,
    SENSOR_10 FLOAT,
    SENSOR_11 FLOAT
);

-- Insert 5000 fake rows with noisy sensor data
INSERT INTO IOT_RAW (
    SENSOR_ID, SENSOR_0, SENSOR_1, SENSOR_2, SENSOR_3, SENSOR_4,
    SENSOR_5, SENSOR_6, SENSOR_7, SENSOR_8, SENSOR_9, SENSOR_10, SENSOR_11
)
SELECT
    UNIFORM(1, 101, RANDOM()) AS SENSOR_ID,
    ROUND(UNIFORM(0.0, 1.0, RANDOM()), 2) AS SENSOR_0,
    ROUND(UNIFORM(20.0, 30.0, RANDOM()), 2) AS SENSOR_1,
    ROUND(UNIFORM(100.0, 130.0, RANDOM()), 2) AS SENSOR_2,
    ROUND(UNIFORM(25.0, 50.0, RANDOM()), 2) AS SENSOR_3,
    ROUND(UNIFORM(90.0, 110.0, RANDOM()), 2) AS SENSOR_4,
    ROUND(UNIFORM(15.0, 20.0, RANDOM()), 2) AS SENSOR_5,
    ROUND(UNIFORM(90.0, 110.0, RANDOM()), 2) AS SENSOR_6,
    ROUND(UNIFORM(10.0, 15.0, RANDOM()), 2) AS SENSOR_7,
    ROUND(UNIFORM(2.0, 4.0, RANDOM()), 2) AS SENSOR_8,
    ROUND(UNIFORM(2.0, 5.0, RANDOM()), 2) AS SENSOR_9,
    ROUND(UNIFORM(0.5, 2.0, RANDOM()), 2) AS SENSOR_10,
    ROUND(UNIFORM(0.0, 1.0, RANDOM()), 2) AS SENSOR_11
FROM TABLE(GENERATOR(ROWCOUNT => 5000));


USE SCHEMA REF_RAW_v001;

CREATE OR REPLACE TABLE REF_DATA_GEOLOC (
    SENSOR_ID NUMBER(6,0),
    CITY VARCHAR(64),
    LATITUDE NUMBER(9,6),
    LONGITUDE NUMBER(9,6)
);

INSERT INTO REF_DATA_GEOLOC (SENSOR_ID, CITY, LATITUDE, LONGITUDE) VALUES
    (1, 'Geneva', 46.195602, 6.148113),
    (2, 'Zürich', 47.366667, 8.550000),
    (3, 'Basel', 47.558395, 7.573271),
    (4, 'Bern', 46.916667, 7.466667),
    (5, 'Lausanne', 46.533333, 6.666667),
    (6, 'Lucerne', 47.083333, 8.266667),
    (7, 'Lugano', 46.009279, 8.955576),
    (8, 'Sankt Fiden', 47.431620, 9.398450),
    (9, 'Chur', 46.856753, 9.526918),
    (10, 'Schaffhausen', 47.697316, 8.634929),
    (11, 'Fribourg', 46.795720, 7.154748),
    (12, 'Neuchâtel', 46.993089, 6.930050),
    (13, 'Tripon', 46.270839, 7.317785),
    (14, 'Zug', 47.172421, 8.517445),
    (15, 'Frauenfeld', 47.559930, 8.899800),
    (16, 'Bellinzona', 46.194902, 9.024729),
    (17, 'Aarau', 47.389616, 8.052354),
    (18, 'Herisau', 47.382710, 9.271860),
    (19, 'Solothurn', 47.206649, 7.516605),
    (20, 'Schwyz', 47.027858, 8.656112),
    (21, 'Liestal', 47.482779, 7.742975),
    (22, 'Delémont', 47.366429, 7.329005),
    (23, 'Sarnen', 46.898509, 8.250681),
    (24, 'Altdorf', 46.880422, 8.644409),
    (25, 'Stansstad', 46.977310, 8.340050),
    (26, 'Glarus', 47.040570, 9.068036),
    (27, 'Appenzell', 47.328414, 9.409647),
    (28, 'Saignelégier', 47.255435, 6.994608),
    (29, 'Affoltern am Albis', 47.281224, 8.453460),
    (30, 'Cully', 46.488301, 6.730109),
    (31, 'Romont', 46.696483, 6.918037),
    (32, 'Aarberg', 47.043835, 7.273570),
    (33, 'Scuol', 46.796756, 10.305946),
    (34, 'Fleurier', 46.903265, 6.582135),
    (35, 'Unterkulm', 47.309980, 8.113710),
    (36, 'Stans', 46.958050, 8.366090),
    (37, 'Lichtensteig', 47.337551, 9.084078),
    (38, 'Yverdon-les-Bains', 46.777908, 6.635502),
    (39, 'Boudry', 46.953019, 6.838970),
    (40, 'Balsthal', 47.315910, 7.693047),
    (41, 'Dornach', 47.478042, 7.616417),
    (42, 'Lachen', 47.199270, 8.854320),
    (43, 'Payerne', 46.822010, 6.936080),
    (44, 'Baden', 47.478029, 8.302764),
    (45, 'Bad Zurzach', 47.589169, 8.289621),
    (46, 'Tafers', 46.814829, 7.218519),
    (47, 'Haslen', 47.369308, 9.367519),
    (48, 'Echallens', 46.642498, 6.637324),
    (49, 'Rapperswil-Jona', 47.228942, 8.833889),
    (50, 'Bulle', 46.619499, 7.056743),
    (51, 'Bülach', 47.518898, 8.536967),
    (52, 'Sankt Gallen', 47.436390, 9.388615),
    (53, 'Wil', 47.460507, 9.043890),
    (54, 'Zofingen', 47.289945, 7.947274),
    (55, 'Vevey', 46.465264, 6.841168),
    (56, 'Renens', 46.539894, 6.588096),
    (57, 'Brugg', 47.481527, 8.203014),
    (58, 'Laufenburg', 47.559248, 8.060446),
    (59, 'La Chaux-de-Fonds', 47.104417, 6.828892),
    (60, 'Andelfingen', 47.594829, 8.679678),
    (61, 'Dietikon', 47.404446, 8.394984),
    (62, 'Winterthur', 47.505640, 8.724130),
    (63, 'Thun', 46.751176, 7.621663),
    (64, 'Le Locle', 47.059533, 6.752278),
    (65, 'Bremgarten', 47.352604, 8.329955),
    (66, 'Tiefencastel', 46.660138, 9.578830),
    (67, 'Saint-Maurice', 46.218257, 7.003196),
    (68, 'Cernier', 47.057356, 6.894757),
    (69, 'Ostermundigen', 46.956112, 7.487187),
    (70, 'Estavayer-le-Lac', 46.849125, 6.845805),
    (71, 'Frutigen', 46.587820, 7.647510),
    (72, 'Muri', 47.270428, 8.338200),
    (73, 'Murten', 46.926840, 7.110343),
    (74, 'Rheinfelden', 47.553587, 7.793839),
    (75, 'Gersau', 46.994189, 8.524996),
    (76, 'Schüpfheim', 46.951613, 8.017235),
    (77, 'Saanen', 46.489557, 7.259609),
    (78, 'Olten', 47.357058, 7.909101),
    (79, 'Domat/Ems', 46.834827, 9.450752),
    (80, 'Münchwilen', 47.477880, 8.995690),
    (81, 'Horgen', 47.255924, 8.598672),
    (82, 'Willisau', 47.119362, 7.991459),
    (83, 'Rorschach', 47.477166, 9.485434),
    (84, 'Morges', 46.511255, 6.495693),
    (85, 'Interlaken', 46.683872, 7.866376),
    (86, 'Sursee', 47.170881, 8.111132),
    (87, 'Küssnacht', 47.085571, 8.442057),
    (88, 'Weinfelden', 47.565710, 9.107010),
    (89, 'Pfäffikon', 47.365728, 8.785950),
    (90, 'Meilen', 47.270429, 8.643675),
    (91, 'Langnau', 46.939360, 7.787380),
    (92, 'Kreuzlingen', 47.650512, 9.175038),
    (93, 'Nidau', 47.129167, 7.238464),
    (94, 'Igis', 46.945308, 9.572180),
    (95, 'Ilanz', 46.773071, 9.204486),
    (96, 'Einsiedeln', 47.128020, 8.743190),
    (97, 'Wangen', 47.231995, 7.654479),
    (98, 'Hinwil', 47.297020, 8.843480),
    (99, 'Hochdorf', 47.168408, 8.291788),
    (100, 'Thusis', 46.697524, 9.440202),
    (101, 'Lenzburg', 47.384048, 8.181798),
    (102, 'Dielsdorf', 47.480247, 8.456280),
    (103, 'Mörel-Filet', 46.355548, 8.044112),
    (104, 'Münster-Geschinen', 46.491704, 8.272063),
    (105, 'Martigny', 46.101915, 7.073989),
    (106, 'Brig-Glis', 46.314500, 7.985796),
    (107, 'Davos', 46.797752, 9.827020),
    (108, 'Uster', 47.352097, 8.716687),
    (109, 'Altstätten', 47.376433, 9.554989),
    (110, 'Courtelary', 47.179369, 7.072954),
    (111, 'Porrentruy', 47.415327, 7.075221);




-- Adding some views
create or replace view REF_RAW_JOIN_SENSOR_GEOLOC(
	SENSOR_ID,
	SENSOR_0,
	CITY,
	LATITUDE,
	LONGITUDE
) as select iot.sensor_id, iot.sensor_0, geo.city, geo.latitude, geo.longitude from IOT_RAW_V001.IOT_RAW as iot
join REF_DATA_GEOLOC as geo on iot.sensor_id = geo.sensor_id;


USE SCHEMA IOT_RAW_v001;

-- Adding some views
create or replace view IOT_RAW_JOIN_SENSOR_GEOLOC(
	SENSOR_ID,
	SENSOR_0,
	CITY,
	LATITUDE,
	LONGITUDE
) as select iot.sensor_id, iot.sensor_0, geo.city, geo.latitude, geo.longitude from IOT_RAW as iot
join REF_RAW_v001.REF_DATA_GEOLOC as geo on iot.sensor_id = geo.sensor_id;


--- create add schema with DataOps database
USE ROLE ACCOUNTADMIN;

DROP SCHEMA IF EXISTS DataOps.CRM_RAW_v001;
CREATE SCHEMA IF NOT EXISTS DataOps.CRM_RAW_v001;
USE SCHEMA CRM_RAW_v001;

GRANT USAGE ON SCHEMA DataOps.CRM_RAW_v001 TO ROLE CICD;
GRANT CREATE TABLE, CREATE VIEW, CREATE STAGE, CREATE FILE FORMAT, CREATE FUNCTION ON SCHEMA DataOps.CRM_RAW_v001 TO ROLE CICD;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA DataOps.CRM_RAW_v001 TO ROLE CICD;
GRANT SELECT, INSERT, UPDATE, DELETE ON FUTURE TABLES IN SCHEMA DataOps.CRM_RAW_v001 TO ROLE CICD;


USE ROLE CICD;
create or replace view CRM_RAW_JOIN_SENSOR_GEOLOC(
	SENSOR_ID,
	SENSOR_0,
	CITY,
	LATITUDE,
	LONGITUDE
) as select iot.sensor_id, iot.sensor_0, geo.city, geo.latitude, geo.longitude from IOT_RAW_v001.IOT_RAW as iot
join REF_RAW_v001.REF_DATA_GEOLOC as geo on iot.sensor_id = geo.sensor_id;


--- create add OPERATIONS database
USE ROLE ACCOUNTADMIN;
DROP DATABASE IF EXISTS OPERATIONS;
CREATE DATABASE IF NOT EXISTS OPERATIONS;
USE DATABASE OPERATIONS;

DROP SCHEMA IF EXISTS PAY_RAW_v001;
CREATE SCHEMA IF NOT EXISTS PAY_RAW_v001;

DROP SCHEMA IF EXISTS CLR_RAW_v001;
CREATE SCHEMA IF NOT EXISTS CLR_RAW_v001 COMMENT = 'Clearing And Settlement';

DROP SCHEMA IF EXISTS CLR_AGG_v001;
CREATE SCHEMA IF NOT EXISTS CLR_AGG_v001 COMMENT = 'Aggregastion layer - Clearing And Settlement';

DROP SCHEMA IF EXISTS CLR_DAP_v001;
CREATE SCHEMA IF NOT EXISTS CLR_DAP_v001 COMMENT = 'Data Products - Clearing And Settlement';


GRANT USAGE ON DATABASE OPERATIONS TO ROLE CICD;
GRANT USAGE ON SCHEMA PAY_RAW_v001 TO ROLE CICD;
GRANT USAGE ON SCHEMA CLR_RAW_v001 TO ROLE CICD;
GRANT USAGE ON SCHEMA CLR_AGG_v001 TO ROLE CICD;
GRANT USAGE ON SCHEMA CLR_DAP_v001 TO ROLE CICD;


GRANT CREATE TABLE, CREATE VIEW, CREATE DYNAMIC TABLE, CREATE STAGE, CREATE FILE FORMAT, CREATE FUNCTION ON SCHEMA PAY_RAW_v001 TO ROLE CICD;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA PAY_RAW_v001 TO ROLE CICD;
GRANT SELECT, INSERT, UPDATE, DELETE ON FUTURE TABLES IN SCHEMA PAY_RAW_v001 TO ROLE CICD;

GRANT CREATE TABLE, CREATE VIEW, CREATE DYNAMIC TABLE, CREATE STAGE, CREATE FILE FORMAT, CREATE FUNCTION ON SCHEMA CLR_RAW_v001 TO ROLE CICD;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA CLR_RAW_v001 TO ROLE CICD;
GRANT SELECT, INSERT, UPDATE, DELETE ON FUTURE TABLES IN SCHEMA CLR_RAW_v001 TO ROLE CICD;

GRANT CREATE TABLE, CREATE VIEW, CREATE DYNAMIC TABLE, CREATE STAGE, CREATE FILE FORMAT, CREATE FUNCTION ON SCHEMA CLR_AGG_v001 TO ROLE CICD;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA CLR_AGG_v001 TO ROLE CICD;
GRANT SELECT, INSERT, UPDATE, DELETE ON FUTURE TABLES IN SCHEMA CLR_AGG_v001 TO ROLE CICD;

GRANT CREATE TABLE, CREATE VIEW, CREATE DYNAMIC TABLE, CREATE STAGE, CREATE FILE FORMAT, CREATE FUNCTION ON SCHEMA CLR_DAP_v001 TO ROLE CICD;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA CLR_DAP_v001 TO ROLE CICD;
GRANT SELECT, INSERT, UPDATE, DELETE ON FUTURE TABLES IN SCHEMA CLR_DAP_v001 TO ROLE CICD;


USE SCHEMA PAY_RAW_v001;
USE ROLE CICD;

-- Create the payment messages table
CREATE OR REPLACE TABLE PAY_RAW_MESSAGES (
    PAYMENT_ID STRING,
    USER_ID STRING,
    AMOUNT NUMBER(10,2),
    CURRENCY STRING,
    STATUS STRING,
    PAYMENT_METHOD STRING,
    TIMESTAMP TIMESTAMP_TZ
);

-- Insert 100 fake payment messages
INSERT INTO PAY_RAW_MESSAGES
SELECT
    UUID_STRING() AS PAYMENT_ID,
    UUID_STRING() AS USER_ID,
    ROUND(UNIFORM(10, 1000, RANDOM()), 2) AS AMOUNT,
    DECODE(UNIFORM(0, 4, RANDOM()),
        0, 'USD',
        1, 'EUR',
        2, 'GBP',
        3, 'JPY'
    ) AS CURRENCY,
    DECODE(UNIFORM(0, 3, RANDOM()),
        0, 'PENDING',
        1, 'COMPLETED',
        2, 'FAILED'
    ) AS STATUS,
    DECODE(UNIFORM(0, 3, RANDOM()),
        0, 'CREDIT_CARD',
        1, 'PAYPAL',
        2, 'BANK_TRANSFER'
    ) AS PAYMENT_METHOD,
    CONVERT_TIMEZONE('UTC', DATEADD(
        SECOND,
        UNIFORM(-86400, 0, RANDOM()),
        CURRENT_TIMESTAMP()
    )) AS TIMESTAMP
FROM TABLE(GENERATOR(ROWCOUNT => 100));


create or replace view PAY_RAW_JOIN_SENSOR_GEOLOC(
	SENSOR_ID,
	SENSOR_0,
	CITY,
	LATITUDE,
	LONGITUDE
) as select iot.sensor_id, iot.sensor_0, geo.city, geo.latitude, geo.longitude from DATAOPS.IOT_RAW_v001.IOT_RAW as iot
join DATAOPS.REF_RAW_v001.REF_DATA_GEOLOC as geo on iot.sensor_id = geo.sensor_id;

---
USE SCHEMA CLR_RAW_v001;
USE ROLE CICD;

CREATE OR REPLACE FILE FORMAT XML_FILE_FORMAT
  TYPE = XML
  STRIP_OUTER_ELEMENT = TRUE;  -- optional, keeps the XML cleaner

CREATE OR REPLACE STAGE ICG_RAW_SWIFT_INBOUND
  FILE_FORMAT = ( 
    TYPE = 'XML' 
  )
  COMMENT = 'Inbound staging area for raw SWIFT ISO20022 XML messages (pacs.008, pacs.002, etc.)';

CREATE OR REPLACE STAGE ICG_RAW_SWIFT_INBOUND_DEV
  FILE_FORMAT = ( 
    TYPE = 'XML' 
  )
  COMMENT = 'Inbound staging area for raw SWIFT ISO20022 XML messages (pacs.008, pacs.002, etc.)';

CREATE OR REPLACE TABLE ICG_RAW_SWIFT_MESSAGES (
    FILE_NAME   STRING,
    LOAD_TS     TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP,
    RAW_XML     VARIANT
);


---
USE SCHEMA CLR_AGG_v001;
USE ROLE CICD;

CREATE OR REPLACE DYNAMIC TABLE ICG_AGG_SWIFT_PACS008
TARGET_LAG = '60 minutes'
WAREHOUSE = MD_TEST_WH
AS
SELECT 
    -- Source metadata
    FILE_NAME as source_filename,
    LOAD_TS as source_load_timestamp,
    
    -- Group Header Information
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[0]."$"[0]."$"')::STRING AS message_id,
    TRY_CAST(GET_PATH(PARSE_XML(RAW_XML::STRING), '$[0]."$"[1]."$"')::STRING AS TIMESTAMP_TZ) AS creation_datetime,

    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[0]."$"[2]."$"')::INTEGER AS number_of_transactions,
    
    -- Group Header Settlement Information
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[0]."$"[3]."@Ccy"')::STRING AS group_settlement_currency,
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[0]."$"[3]."$"')::DECIMAL(18,2) AS group_settlement_amount,
    
    -- Settlement Information
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[0]."$"[4]."$"[0]."$"')::STRING AS settlement_method,
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[0]."$"[4]."$"[1]."$"."$"')::STRING AS clearing_system_code,
    
    -- Payment Identification
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[0]."$"[0]."$"')::STRING AS instruction_id,
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[0]."$"[1]."$"')::STRING AS end_to_end_id,
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[0]."$"[2]."$"')::STRING AS transaction_id,
    
    -- Payment Type Information
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[1]."$"[0]."$"')::STRING AS instruction_priority,
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[1]."$"[1]."$"."$"')::STRING AS service_level_code,
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[1]."$"[2]."$"."$"')::STRING AS local_instrument_code,
    
    -- Transaction Amount
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[2]."@Ccy"')::STRING AS transaction_currency,
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[2]."$"')::DECIMAL(18,2) AS transaction_amount,
    
    -- Settlement Date and Charges
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[3]."$"')::DATE AS interbank_settlement_date,
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[4]."$"')::STRING AS charges_bearer,
    
    -- Agent Information
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[5]."$"."$"."$"')::STRING AS instructing_agent_bic,
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[6]."$"."$"."$"')::STRING AS instructed_agent_bic,
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[7]."$"."$"."$"')::STRING AS debtor_agent_bic,
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[8]."$"."$"."$"')::STRING AS creditor_agent_bic,
    
    -- Debtor Information
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[9]."$"[0]."$"')::STRING AS debtor_name,
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[9]."$"[1]."$"[0]."$"')::STRING AS debtor_street,
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[9]."$"[1]."$"[1]."$"')::STRING AS debtor_postal_code,
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[9]."$"[1]."$"[2]."$"')::STRING AS debtor_city,
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[9]."$"[1]."$"[3]."$"')::STRING AS debtor_country,
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[10]."$"."$"."$"')::STRING AS debtor_iban,
    
    -- Creditor Information
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[11]."$"[0]."$"')::STRING AS creditor_name,
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[11]."$"[1]."$"[0]."$"')::STRING AS creditor_street,
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[11]."$"[1]."$"[1]."$"')::STRING AS creditor_postal_code,
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[11]."$"[1]."$"[2]."$"')::STRING AS creditor_city,
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[11]."$"[1]."$"[3]."$"')::STRING AS creditor_country,
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[12]."$"."$"."$"')::STRING AS creditor_iban,
    
    -- Remittance Information
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[13]."$"."$"')::STRING AS remittance_information,
    
    -- Analytics Fields
    CASE 
        WHEN GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[2]."$"')::DECIMAL(18,2) >= 100000 THEN TRUE
        ELSE FALSE
    END AS is_high_value_payment,
    
    CASE 
        WHEN GET_PATH(PARSE_XML(RAW_XML::STRING), '$[0]."$"[4]."$"[1]."$"."$"')::STRING = 'TARGET2' THEN TRUE
        ELSE FALSE
    END AS is_target2_payment,
    
    CONCAT(
        COALESCE(GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[9]."$"[1]."$"[3]."$"')::STRING, 'UNKNOWN'),
        ' -> ',
        COALESCE(GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[11]."$"[1]."$"[3]."$"')::STRING, 'UNKNOWN')
    ) AS payment_corridor,
    
    CASE 
        WHEN GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[9]."$"[1]."$"[3]."$"')::STRING = 
             GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[11]."$"[1]."$"[3]."$"')::STRING THEN 'DOMESTIC'
        ELSE 'CROSS_BORDER'
    END AS payment_type_classification,
    
    -- Processing metadata
    CURRENT_TIMESTAMP() AS parsed_at,
    LENGTH(RAW_XML::STRING) AS xml_size_bytes

FROM CLR_RAW_v001.ICG_RAW_SWIFT_MESSAGES
WHERE RAW_XML IS NOT NULL
  AND (FILE_NAME ILIKE '%pacs008%' OR RAW_XML::STRING ILIKE '%FIToFICstmrCdtTrf%');


CREATE OR REPLACE DYNAMIC TABLE ICG_AGG_SWIFT_PACS002
TARGET_LAG = '60 minutes'
WAREHOUSE = MD_TEST_WH
AS
SELECT 
    -- Source metadata
    FILE_NAME as source_filename,
    LOAD_TS as source_load_timestamp,
    
    -- Group Header Information (array index 0)
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[0]."$"[0]."$"')::STRING AS message_id,
    TRY_CAST(GET_PATH(PARSE_XML(RAW_XML::STRING), '$[0]."$"[1]."$"')::STRING AS TIMESTAMP_TZ) AS creation_datetime, -- <CreDtTm>

    
    -- Agent Information from Group Header
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[0]."$"[2]."$"."$"."$"')::STRING AS instructing_agent_bic,
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[0]."$"[3]."$"."$"."$"')::STRING AS instructed_agent_bic,
    
    -- Original Group Information and Status (array index 1)
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[0]."$"')::STRING AS original_message_id,
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[1]."$"')::STRING AS original_message_name_id,
    TRY_CAST(GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[2]."$"')::STRING AS TIMESTAMP_TZ) AS original_creation_datetime, -- <OrgnlCreDtTm>
    
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[3]."$"')::STRING AS group_status,
    
    -- Transaction Information and Status (array index 2)
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[2]."$"[0]."$"')::STRING AS original_end_to_end_id,
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[2]."$"[1]."$"')::STRING AS transaction_status,
    
    -- Status Reason Information
    GET_PATH(PARSE_XML(RAW_XML::STRING), '$[2]."$"[2]."$"."$"')::STRING AS status_reason,
    
    -- Additional fields that might be present (with safe extraction)
    TRY_CAST(GET_PATH(PARSE_XML(RAW_XML::STRING), '$[2]."$"[3]."$"')::STRING AS STRING) AS original_instruction_id,
    TRY_CAST(GET_PATH(PARSE_XML(RAW_XML::STRING), '$[2]."$"[4]."$"')::STRING AS STRING) AS original_transaction_id,
    TRY_CAST(GET_PATH(PARSE_XML(RAW_XML::STRING), '$[2]."$"[5]."$"')::STRING AS TIMESTAMP_TZ) AS acceptance_datetime,
    
    -- Derived Analytics Fields
    CASE 
        WHEN GET_PATH(PARSE_XML(RAW_XML::STRING), '$[2]."$"[1]."$"')::STRING = 'ACCP' THEN 'ACCEPTED'
        WHEN GET_PATH(PARSE_XML(RAW_XML::STRING), '$[2]."$"[1]."$"')::STRING = 'RJCT' THEN 'REJECTED'
        WHEN GET_PATH(PARSE_XML(RAW_XML::STRING), '$[2]."$"[1]."$"')::STRING = 'PDNG' THEN 'PENDING'
        WHEN GET_PATH(PARSE_XML(RAW_XML::STRING), '$[2]."$"[1]."$"')::STRING = 'ACSC' THEN 'ACCEPTED_SETTLEMENT_COMPLETED'
        WHEN GET_PATH(PARSE_XML(RAW_XML::STRING), '$[2]."$"[1]."$"')::STRING = 'ACSP' THEN 'ACCEPTED_SETTLEMENT_IN_PROCESS'
        ELSE GET_PATH(PARSE_XML(RAW_XML::STRING), '$[2]."$"[1]."$"')::STRING
    END AS transaction_status_description,
    
    CASE 
        WHEN GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[3]."$"')::STRING = 'ACCP' THEN 'ACCEPTED'
        WHEN GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[3]."$"')::STRING = 'RJCT' THEN 'REJECTED'
        WHEN GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[3]."$"')::STRING = 'PDNG' THEN 'PENDING'
        ELSE GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[3]."$"')::STRING
    END AS group_status_description,
    
    -- Check if this is a positive or negative response
    CASE 
        WHEN GET_PATH(PARSE_XML(RAW_XML::STRING), '$[2]."$"[1]."$"')::STRING IN ('ACCP', 'ACSC', 'ACSP') THEN TRUE
        ELSE FALSE
    END AS is_positive_response,
    
    CASE 
        WHEN GET_PATH(PARSE_XML(RAW_XML::STRING), '$[2]."$"[1]."$"')::STRING = 'RJCT' THEN TRUE
        ELSE FALSE
    END AS is_rejection,
    
    -- Check if this is related to PACS.008
    CASE 
        WHEN GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[1]."$"')::STRING = 'pacs.008.001.08' THEN TRUE
        ELSE FALSE
    END AS is_pacs008_response,
    
    -- Extract date from original message ID for correlation
    CASE 
        WHEN GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[0]."$"')::STRING LIKE '20%-%-%' THEN
            SUBSTR(GET_PATH(PARSE_XML(RAW_XML::STRING), '$[1]."$"[0]."$"')::STRING, 1, 8)
        ELSE NULL
    END AS original_message_date,
    
    -- Processing metadata
    CURRENT_TIMESTAMP() AS parsed_at,
    LENGTH(RAW_XML::STRING) AS xml_size_bytes

FROM CLR_RAW_v001.ICG_RAW_SWIFT_MESSAGES
WHERE RAW_XML IS NOT NULL
  AND (FILE_NAME ILIKE '%pacs002%' OR RAW_XML::STRING ILIKE '%FIToFIPmtStsRpt%');



---
USE SCHEMA CLR_DAP_v001;
USE ROLE CICD;

CREATE OR REPLACE DYNAMIC TABLE ICG_DAP_SWIFT_JOIN_PACS008_002
TARGET_LAG = '60 minutes'
WAREHOUSE = MD_TEST_WH
AS
SELECT
    -- Join keys
    p008.message_id                AS pacs008_message_id,
    p002.original_message_id       AS pacs002_original_message_id,
    
    -- Transaction-level correlation
    p008.end_to_end_id             AS pacs008_end_to_end_id,
    p002.original_end_to_end_id    AS pacs002_original_end_to_end_id,
    
    -- Status from pacs.002
    p002.transaction_status,
    p002.transaction_status_description,
    p002.group_status,
    p002.group_status_description,
    p002.status_reason,
    p002.is_rejection,
    p002.is_positive_response,
    
    -- Payment details from pacs.008
    p008.transaction_currency,
    p008.transaction_amount,
    p008.debtor_name,
    p008.creditor_name,
    p008.payment_corridor,
    p008.payment_type_classification,
    p008.is_high_value_payment,
    p008.is_target2_payment,
    
    -- Metadata
    p008.source_filename   AS pacs008_file,
    p002.source_filename   AS pacs002_file,
    p008.source_load_timestamp AS pacs008_load_timestamp,
    p002.source_load_timestamp AS pacs002_load_timestamp,
    DATEDIFF('minutes', p002.ORIGINAL_CREATION_DATETIME, p002.CREATION_DATETIME) AS ack_time,
    CURRENT_TIMESTAMP() AS joined_at
    
FROM CLR_AGG_v001.ICG_AGG_SWIFT_PACS008 p008
LEFT JOIN CLR_AGG_v001.ICG_AGG_SWIFT_PACS002 p002
    ON p002.original_message_id = p008.message_id
   AND (
        p002.original_end_to_end_id = p008.end_to_end_id
        OR p002.original_transaction_id = p008.transaction_id
   );




---
USE ROLE ACCOUNTADMIN;
USE DATABASE DATAOPS;
USE SCHEMA IOT_RAW_v001;

CREATE or ALTER authentication policy CICD_AUTH_POLICY
  authentication_methods = ('PASSWORD', 'OAUTH', 'KEYPAIR', 'PROGRAMMATIC_ACCESS_TOKEN')
  pat_policy = (
    default_expiry_in_days=7,
    max_expiry_in_days=90,
    network_policy_evaluation = ENFORCED_NOT_REQUIRED
  );
