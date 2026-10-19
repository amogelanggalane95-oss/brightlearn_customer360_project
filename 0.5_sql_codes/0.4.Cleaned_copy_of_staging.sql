
-- Cleaned copy of staging: trims text, turns blanks into 'Unknown',
-- and converts text to proper DATE / DECIMAL types
CREATE OR ALTER VIEW dbo.vw_clean_activity AS
SELECT
    LTRIM(RTRIM(client_number))                                            AS client_number,
    ISNULL(NULLIF(LTRIM(RTRIM(first_name)), ''), 'Unknown')                AS first_name,
    ISNULL(NULLIF(LTRIM(RTRIM(last_name)), ''), 'Unknown')                 AS last_name,
    ISNULL(NULLIF(LTRIM(RTRIM(email)), ''), 'Unknown')                     AS email,
    ISNULL(NULLIF(LTRIM(RTRIM(mobile_number)), ''), 'Unknown')             AS mobile_number,
    TRY_CAST(NULLIF(LTRIM(RTRIM(date_of_birth)), '') AS DATE)              AS date_of_birth,
    CASE WHEN LTRIM(RTRIM(gender)) IN ('M', 'F')
         THEN LTRIM(RTRIM(gender)) ELSE 'Unknown' END                      AS gender,
    ISNULL(NULLIF(LTRIM(RTRIM(province)), ''), 'Unknown')                  AS province,
    ISNULL(NULLIF(LTRIM(RTRIM(city)), ''), 'Unknown')                      AS city,
    TRY_CAST(NULLIF(LTRIM(RTRIM(signup_date)), '') AS DATE)                AS signup_date,
    ISNULL(NULLIF(LTRIM(RTRIM(event_type)), ''), 'Unknown')                AS event_type,
    TRY_CAST(NULLIF(LTRIM(RTRIM(event_date)), '') AS DATE)                 AS event_date,
    ISNULL(NULLIF(LTRIM(RTRIM(account_number)), ''), 'Unknown')            AS account_number,
    ISNULL(NULLIF(LTRIM(RTRIM(product_type)), ''), 'Unknown')              AS product_type,
    ISNULL(NULLIF(LTRIM(RTRIM(account_status)), ''), 'Unknown')            AS account_status,
    TRY_CAST(NULLIF(LTRIM(RTRIM(credit_limit)), '') AS DECIMAL(12,2))      AS credit_limit,
    TRY_CAST(NULLIF(LTRIM(RTRIM(loan_amount)), '') AS DECIMAL(12,2))       AS loan_amount,
    TRY_CAST(NULLIF(LTRIM(RTRIM(account_balance)), '') AS DECIMAL(12,2))   AS account_balance,
    ISNULL(NULLIF(LTRIM(RTRIM(channel)), ''), 'Unknown')                   AS channel,
    ISNULL(NULLIF(LTRIM(RTRIM(interaction_type)), ''), 'Unknown')          AS interaction_type,
    ISNULL(NULLIF(LTRIM(RTRIM(resolved_flag)), ''), 'Unknown')             AS resolved_flag,
    ISNULL(NULLIF(LTRIM(RTRIM(transaction_type)), ''), 'Unknown')          AS transaction_type,
    TRY_CAST(NULLIF(LTRIM(RTRIM(amount)), '') AS DECIMAL(12,2))            AS amount
FROM stg_Customer360.dbo.customer_activity;
GO



