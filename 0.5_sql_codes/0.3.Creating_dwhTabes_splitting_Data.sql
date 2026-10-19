-- Sanity check on staging (expect 21500)
SELECT COUNT(*) AS rows_loaded FROM stg_Customer360.dbo.customer_activity;
SELECT event_type, COUNT(*) AS n FROM stg_Customer360.dbo.customer_activity GROUP BY event_type;
GO

--creating dwhTables

IF OBJECT_ID('dbo.dim_customer', 'U') IS NULL
CREATE TABLE dbo.dim_customer (
    customer_id      INT IDENTITY(1,1) PRIMARY KEY,
    customer_number  VARCHAR(20),
    firstname        VARCHAR(100),
    lastname         VARCHAR(100),
    date_of_birth    DATE,
    gender           VARCHAR(10)
);

IF OBJECT_ID('dbo.dim_customer_contact', 'U') IS NULL
CREATE TABLE dbo.dim_customer_contact (
    contact_id       INT IDENTITY(1,1) PRIMARY KEY,
    email            VARCHAR(200),
    mobile_number    VARCHAR(50)
);

IF OBJECT_ID('dbo.dim_location', 'U') IS NULL
CREATE TABLE dbo.dim_location (
    location_id      INT IDENTITY(1,1) PRIMARY KEY,
    province         VARCHAR(100),
    city             VARCHAR(100)
);

IF OBJECT_ID('dbo.dim_interaction', 'U') IS NULL
CREATE TABLE dbo.dim_interaction (
    interaction_id   INT IDENTITY(1,1) PRIMARY KEY,
    interaction_type VARCHAR(50),
    resolved_flag    VARCHAR(10)
);

IF OBJECT_ID('dbo.dim_event', 'U') IS NULL
CREATE TABLE dbo.dim_event (
    event_id         INT IDENTITY(1,1) PRIMARY KEY,
    event_type       VARCHAR(30)
);

IF OBJECT_ID('dbo.dim_account', 'U') IS NULL
CREATE TABLE dbo.dim_account (
    account_id       INT IDENTITY(1,1) PRIMARY KEY,
    account_number   VARCHAR(20),
    account_status   VARCHAR(20),
    product_type     VARCHAR(50)
);

IF OBJECT_ID('dbo.dim_transaction', 'U') IS NULL
CREATE TABLE dbo.dim_transaction (
    transaction_id   INT IDENTITY(1,1) PRIMARY KEY,
    transaction_type VARCHAR(50),
    channel          VARCHAR(50)
);

IF OBJECT_ID('dbo.dim_dates', 'U') IS NULL
CREATE TABLE dbo.dim_dates (
    dates_id         INT IDENTITY(1,1) PRIMARY KEY,
    signup_date      DATE,
    event_date       DATE,
    event_year       INT,
    event_month      INT
);

--loading dwhTables

-- dim_customer: one row per customer_number
INSERT INTO dbo.dim_customer (customer_number, firstname, lastname, date_of_birth, gender)
SELECT DISTINCT v.client_number, v.first_name, v.last_name, v.date_of_birth, v.gender
FROM dbo.vw_clean_activity v
WHERE NOT EXISTS (SELECT 1 FROM dbo.dim_customer d
                  WHERE d.customer_number = v.client_number);

-- dim_customer_contact: one row per email + mobile number
INSERT INTO dbo.dim_customer_contact (email, mobile_number)
SELECT DISTINCT v.email, v.mobile_number
FROM dbo.vw_clean_activity v
WHERE NOT EXISTS (SELECT 1 FROM dbo.dim_customer_contact d
                  WHERE d.email = v.email AND d.mobile_number = v.mobile_number);

-- dim_location: one row per province + city
INSERT INTO dbo.dim_location (province, city)
SELECT DISTINCT v.province, v.city
FROM dbo.vw_clean_activity v
WHERE NOT EXISTS (SELECT 1 FROM dbo.dim_location d
                  WHERE d.province = v.province AND d.city = v.city);

-- dim_interaction: one row per interaction type + resolved flag
INSERT INTO dbo.dim_interaction (interaction_type, resolved_flag)
SELECT DISTINCT v.interaction_type, v.resolved_flag
FROM dbo.vw_clean_activity v
WHERE NOT EXISTS (SELECT 1 FROM dbo.dim_interaction d
                  WHERE d.interaction_type = v.interaction_type
                    AND d.resolved_flag = v.resolved_flag);

-- dim_event: one row per event type
INSERT INTO dbo.dim_event (event_type)
SELECT DISTINCT v.event_type
FROM dbo.vw_clean_activity v
WHERE NOT EXISTS (SELECT 1 FROM dbo.dim_event d
                  WHERE d.event_type = v.event_type);

-- dim_account: one row per account_number
-- (a) accounts from 'Product Enrollment' rows first, because only they carry the status
INSERT INTO dbo.dim_account (account_number, account_status, product_type)
SELECT DISTINCT v.account_number, v.account_status, v.product_type
FROM dbo.vw_clean_activity v
WHERE v.event_type = 'Product Enrollment'
  AND NOT EXISTS (SELECT 1 FROM dbo.dim_account d
                  WHERE d.account_number = v.account_number);

-- (b) any account that never had an enrollment row (plus the 'Unknown' account
--     used by CRM rows that have no account) is added with status 'Unknown'
INSERT INTO dbo.dim_account (account_number, account_status, product_type)
SELECT DISTINCT v.account_number, 'Unknown', v.product_type
FROM dbo.vw_clean_activity v
WHERE NOT EXISTS (SELECT 1 FROM dbo.dim_account d
                  WHERE d.account_number = v.account_number);

-- dim_transaction: one row per transaction type + channel
INSERT INTO dbo.dim_transaction (transaction_type, channel)
SELECT DISTINCT v.transaction_type, v.channel
FROM dbo.vw_clean_activity v
WHERE NOT EXISTS (SELECT 1 FROM dbo.dim_transaction d
                  WHERE d.transaction_type = v.transaction_type
                    AND d.channel = v.channel);

-- dim_dates: one row per signup_date + event_date
INSERT INTO dbo.dim_dates (signup_date, event_date, event_year, event_month)
SELECT DISTINCT v.signup_date, v.event_date, YEAR(v.event_date), MONTH(v.event_date)
FROM dbo.vw_clean_activity v
WHERE NOT EXISTS (SELECT 1 FROM dbo.dim_dates d
                  WHERE d.signup_date = v.signup_date
                    AND d.event_date = v.event_date);
GO