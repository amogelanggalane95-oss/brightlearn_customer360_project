/* =====================================================================
   PART 2 - VALIDATE THE BUILD
   rows_in_dwh should equal rows_expected on every line
   ===================================================================== */

SELECT 'dim_customer' AS table_name,
       (SELECT COUNT(*) FROM dbo.dim_customer) AS rows_in_dwh,
       (SELECT COUNT(DISTINCT client_number) FROM dbo.vw_clean_activity) AS rows_expected
UNION ALL SELECT 'dim_customer_contact',
       (SELECT COUNT(*) FROM dbo.dim_customer_contact),
       (SELECT COUNT(*) FROM (SELECT DISTINCT email, mobile_number FROM dbo.vw_clean_activity) x)
UNION ALL SELECT 'dim_location',
       (SELECT COUNT(*) FROM dbo.dim_location),
       (SELECT COUNT(*) FROM (SELECT DISTINCT province, city FROM dbo.vw_clean_activity) x)
UNION ALL SELECT 'dim_interaction',
       (SELECT COUNT(*) FROM dbo.dim_interaction),
       (SELECT COUNT(*) FROM (SELECT DISTINCT interaction_type, resolved_flag FROM dbo.vw_clean_activity) x)
UNION ALL SELECT 'dim_event',
       (SELECT COUNT(*) FROM dbo.dim_event),
       (SELECT COUNT(DISTINCT event_type) FROM dbo.vw_clean_activity)
UNION ALL SELECT 'dim_account',
       (SELECT COUNT(*) FROM dbo.dim_account),
       (SELECT COUNT(DISTINCT account_number) FROM dbo.vw_clean_activity)
UNION ALL SELECT 'dim_transaction',
       (SELECT COUNT(*) FROM dbo.dim_transaction),
       (SELECT COUNT(*) FROM (SELECT DISTINCT transaction_type, channel FROM dbo.vw_clean_activity) x)
UNION ALL SELECT 'dim_dates',
       (SELECT COUNT(*) FROM dbo.dim_dates),
       (SELECT COUNT(*) FROM (SELECT DISTINCT signup_date, event_date FROM dbo.vw_clean_activity) x)
UNION ALL SELECT 'dim_fact  (exact duplicate rows are removed)',
       (SELECT COUNT(*) FROM dbo.dim_fact),
       (SELECT COUNT(*) FROM (SELECT DISTINCT * FROM dbo.vw_clean_activity) x);


       -- Join everything back together to see that the split works
SELECT TOP 20
    cu.firstname, cu.lastname, ev.event_type, ac.account_number, ac.product_type,
    tr.transaction_type, tr.channel, da.event_date, f.amount, f.account_balance
FROM dbo.dim_fact f
JOIN dbo.dim_customer    cu ON cu.customer_id    = f.customer_id
JOIN dbo.dim_event       ev ON ev.event_id       = f.event_id
JOIN dbo.dim_account     ac ON ac.account_id     = f.account_id
JOIN dbo.dim_transaction tr ON tr.transaction_id = f.transaction_id
JOIN dbo.dim_dates       da ON da.dates_id       = f.dates_id
ORDER BY f.UniqueID;
GO