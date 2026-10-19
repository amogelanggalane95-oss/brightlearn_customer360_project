/* =====================================================================
   PART 3 - HELPER VIEWS (used by several questions
   ===================================================================== */

-- One row per customer with their province / city
CREATE OR ALTER VIEW dbo.vw_customer_location AS
SELECT x.customer_id, l.province, l.city
FROM (SELECT customer_id, MIN(location_id) AS location_id
      FROM dbo.dim_fact
      GROUP BY customer_id) x
JOIN dbo.dim_location l ON l.location_id = x.location_id;
GO

-- One row per customer with their signup date
CREATE OR ALTER VIEW dbo.vw_customer_signup AS
SELECT f.customer_id, MIN(dt.signup_date) AS signup_date
FROM dbo.dim_fact f
JOIN dbo.dim_dates dt ON dt.dates_id = f.dates_id
GROUP BY f.customer_id;
GO

-- The latest date anywhere in the data. Used instead of GETDATE()
-- because this is a static extract: "today" = the last recorded event.
CREATE OR ALTER VIEW dbo.vw_latest_date AS
SELECT MAX(dt.event_date) AS latest_date
FROM dbo.dim_fact f
JOIN dbo.dim_dates dt ON dt.dates_id = f.dates_id;
GO

-- The latest TRANSACTION date (Q12 asks for this specific reference point)
CREATE OR ALTER VIEW dbo.vw_latest_txn_date AS
SELECT MAX(dt.event_date) AS latest_txn_date
FROM dbo.dim_fact f
JOIN dbo.dim_dates dt ON dt.dates_id = f.dates_id
JOIN dbo.dim_event ev ON ev.event_id = f.event_id
WHERE ev.event_type = 'Transaction';
GO

-- Each customer's most recent Transaction or CRM Interaction date
CREATE OR ALTER VIEW dbo.vw_customer_last_activity AS
SELECT f.customer_id, MAX(dt.event_date) AS last_activity_date
FROM dbo.dim_fact f
JOIN dbo.dim_dates dt ON dt.dates_id = f.dates_id
JOIN dbo.dim_event ev ON ev.event_id = f.event_id
WHERE ev.event_type IN ('Transaction', 'CRM Interaction')
GROUP BY f.customer_id;
GO

-- One row per customer per product they hold
-- Definition: a customer "holds" a product if they have a Product
-- Enrollment event for an account of that product type.
CREATE OR ALTER VIEW dbo.vw_customer_product AS
SELECT DISTINCT f.customer_id, ac.product_type
FROM dbo.dim_fact f
JOIN dbo.dim_account ac ON ac.account_id = f.account_id
JOIN dbo.dim_event ev ON ev.event_id = f.event_id
WHERE ev.event_type = 'Product Enrollment'
  AND ac.product_type <> 'Unknown';
GO

-- One row per account: its most recent Product Enrollment record
-- (so an account that has more than one enrollment row is not counted twice)
CREATE OR ALTER VIEW dbo.vw_account_snapshot AS
SELECT account_id, product_type, account_status,
       account_balance, credit_limit, loan_amount
FROM (
    SELECT f.account_id, ac.product_type, ac.account_status,
           f.account_balance, f.credit_limit, f.loan_amount,
           ROW_NUMBER() OVER (PARTITION BY f.account_id
                              ORDER BY dt.event_date DESC, f.UniqueID DESC) AS rn
    FROM dbo.dim_fact f
    JOIN dbo.dim_account ac ON ac.account_id = f.account_id
    JOIN dbo.dim_dates dt ON dt.dates_id = f.dates_id
    JOIN dbo.dim_event ev ON ev.event_id = f.event_id
    WHERE ev.event_type = 'Product Enrollment'
) x
WHERE rn = 1;
GO


-- Quick look at the exact values in the data. The questions below use
-- these spellings: 'Transaction', 'CRM Interaction', 'Product Enrollment',
-- 'Savings', 'Credit Card', 'Complaint', 'Y' / 'N'.
-- If any value here is spelled differently, change it in the queries.
SELECT 'event_type' AS column_name, event_type AS value FROM dbo.dim_event
UNION ALL SELECT DISTINCT 'product_type',     product_type     FROM dbo.dim_account
UNION ALL SELECT DISTINCT 'account_status',   account_status   FROM dbo.dim_account
UNION ALL SELECT DISTINCT 'interaction_type', interaction_type FROM dbo.dim_interaction
UNION ALL SELECT DISTINCT 'resolved_flag',    resolved_flag    FROM dbo.dim_interaction
UNION ALL SELECT DISTINCT 'transaction_type', transaction_type FROM dbo.dim_transaction
UNION ALL SELECT DISTINCT 'channel',          channel          FROM dbo.dim_transaction
ORDER BY column_name, value;
GO