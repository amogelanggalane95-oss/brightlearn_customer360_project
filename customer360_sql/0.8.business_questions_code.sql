/* =========================================================================
   CUSTOMER BASE
   ========================================================================= */

-- Q1. Customers per province and share of the total
SELECT
    province,
    COUNT(*) AS customer_count,
    CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS pct_of_total
FROM dbo.vw_customer_location
GROUP BY province
ORDER BY customer_count DESC;


-- Q2. Age distribution
-- Definition: age = whole years between date_of_birth and the latest date
-- in the data (static extract, so "today" does not apply).
-- Bands: 18-24, 25-34, 35-44, 45-54, 55-64, 65+ (plus 'Under 18' for
-- impossible/invalid dates of birth and 'Unknown' for missing ones).
-- Why these bands: they follow common life stages in retail banking
-- (young adult, building a career, established, pre-retirement,
-- retirement) rather than arbitrary 10-year slices.
;WITH ages AS (
    SELECT
        cu.customer_id,
        CASE WHEN cu.date_of_birth IS NULL THEN NULL
             ELSE DATEDIFF(YEAR, cu.date_of_birth, ld.latest_date)
                  - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, cu.date_of_birth, ld.latest_date), cu.date_of_birth) > ld.latest_date
                         THEN 1 ELSE 0 END
        END AS age
    FROM dbo.dim_customer cu
    CROSS JOIN dbo.vw_latest_date ld
),
banded AS (
    SELECT
        age,
        CASE WHEN age IS NULL THEN 'Unknown'
             WHEN age < 18    THEN 'Under 18'
             WHEN age <= 24   THEN '18-24'
             WHEN age <= 34   THEN '25-34'
             WHEN age <= 44   THEN '35-44'
             WHEN age <= 54   THEN '45-54'
             WHEN age <= 64   THEN '55-64'
             ELSE '65+' END AS age_band
    FROM ages
)
SELECT age_band, COUNT(*) AS customer_count
FROM banded
GROUP BY age_band
ORDER BY CASE WHEN age_band = 'Unknown' THEN 1 ELSE 0 END, MIN(age);


-- Q3. Signups per month over the last 24 months of data, and the trend
-- (the most recent month may be partial if the data stops mid-month)
IF OBJECT_ID('tempdb..#monthly_signups') IS NOT NULL DROP TABLE #monthly_signups;

SELECT
    DATEFROMPARTS(YEAR(cs.signup_date), MONTH(cs.signup_date), 1) AS signup_month,
    COUNT(*) AS signups
INTO #monthly_signups
FROM dbo.vw_customer_signup cs
CROSS JOIN dbo.vw_latest_date ld
WHERE cs.signup_date >= DATEADD(MONTH, -23, DATEFROMPARTS(YEAR(ld.latest_date), MONTH(ld.latest_date), 1))
  AND cs.signup_date <= ld.latest_date
GROUP BY DATEFROMPARTS(YEAR(cs.signup_date), MONTH(cs.signup_date), 1);

-- Q3a. The monthly numbers
SELECT
    CONVERT(VARCHAR(7), signup_month, 120) AS month_label,
    signups,
    signups - LAG(signups) OVER (ORDER BY signup_month) AS change_vs_prev_month
FROM #monthly_signups
ORDER BY signup_month;

-- Q3b. Trend: average monthly signups in the first half of the period vs
-- the second half. More than 10% higher = up, more than 10% lower = down,
-- otherwise flat.
SELECT
    avg_first_half,
    avg_second_half,
    CASE WHEN avg_second_half > avg_first_half * 1.10 THEN 'Trending up'
         WHEN avg_second_half < avg_first_half * 0.90 THEN 'Trending down'
         ELSE 'Roughly flat' END AS trend
FROM (
    SELECT
        AVG(CASE WHEN rn <= half THEN signups * 1.0 END) AS avg_first_half,
        AVG(CASE WHEN rn >  half THEN signups * 1.0 END) AS avg_second_half
    FROM (
        SELECT signups,
               ROW_NUMBER() OVER (ORDER BY signup_month) AS rn,
               COUNT(*) OVER () / 2 AS half
        FROM #monthly_signups
    ) x
) y;


-- Q4. Customer records that look like data-quality problems
-- Definitions:
--   missing contact    = the customer has no valid-looking email
--                        (needs an @ and a dot) OR no mobile number,
--                        in any of their records
--   duplicate identity = same first name + last name + date of birth
--                        shared by more than one customer_number
--                        ('Unknown' names and missing birth dates are
--                        ignored, otherwise every blank would match)
-- Counts are customer records, not groups.
;WITH contact_check AS (
    SELECT
        f.customer_id,
        MAX(CASE WHEN co.email LIKE '%_@_%._%' THEN 1 ELSE 0 END) AS has_valid_email,
        MAX(CASE WHEN co.mobile_number <> 'Unknown' THEN 1 ELSE 0 END) AS has_mobile
    FROM dbo.dim_fact f
    JOIN dbo.dim_customer_contact co ON co.contact_id = f.contact_id
    GROUP BY f.customer_id
),
duplicate_check AS (
    SELECT cu.customer_id
    FROM dbo.dim_customer cu
    JOIN (SELECT firstname, lastname, date_of_birth
          FROM dbo.dim_customer
          WHERE firstname <> 'Unknown'
            AND lastname <> 'Unknown'
            AND date_of_birth IS NOT NULL
          GROUP BY firstname, lastname, date_of_birth
          HAVING COUNT(DISTINCT customer_number) > 1) d
      ON  d.firstname     = cu.firstname
      AND d.lastname      = cu.lastname
      AND d.date_of_birth = cu.date_of_birth
)
SELECT
    COUNT(*) AS total_customers,
    SUM(CASE WHEN ISNULL(cc.has_valid_email, 0) = 0
               OR ISNULL(cc.has_mobile, 0) = 0 THEN 1 ELSE 0 END) AS missing_contact,
    SUM(CASE WHEN dc.customer_id IS NOT NULL THEN 1 ELSE 0 END)   AS duplicate_identity,
    SUM(CASE WHEN ISNULL(cc.has_valid_email, 0) = 0
               OR ISNULL(cc.has_mobile, 0) = 0
               OR dc.customer_id IS NOT NULL THEN 1 ELSE 0 END)   AS any_problem,
    CAST(SUM(CASE WHEN ISNULL(cc.has_valid_email, 0) = 0
                    OR ISNULL(cc.has_mobile, 0) = 0
                    OR dc.customer_id IS NOT NULL THEN 1 ELSE 0 END) * 100.0
         / COUNT(*) AS DECIMAL(5,2)) AS pct_any_problem
FROM dbo.dim_customer cu
LEFT JOIN contact_check   cc ON cc.customer_id = cu.customer_id
LEFT JOIN duplicate_check dc ON dc.customer_id = cu.customer_id;


/* =========================================================================
   PRODUCTS
   ========================================================================= */

-- Q5. Customers per product type, and customers holding 2+ products
-- Definition: "holds" = has a Product Enrollment for that product
-- (account status is not filtered; see the account_status values in
-- the lookup in Part 3 if you want to exclude closed accounts).
SELECT product_type, COUNT(*) AS customer_count
FROM dbo.vw_customer_product
GROUP BY product_type

UNION ALL

SELECT 'Holds 2+ products', COUNT(*)
FROM (SELECT customer_id
      FROM dbo.vw_customer_product
      GROUP BY customer_id
      HAVING COUNT(*) > 1) x;


-- Q6. Total and average account balance by product type
-- One balance per account (its latest enrollment record).
SELECT
    product_type,
    COUNT(*)             AS accounts,
    SUM(account_balance) AS total_balance,
    AVG(account_balance) AS avg_balance
FROM dbo.vw_account_snapshot
GROUP BY product_type
ORDER BY product_type;


-- Q7. Customers with a Savings account but no Credit Card (cross-sell list)
-- Q7a. The count
SELECT COUNT(*) AS savings_but_no_credit_card
FROM (SELECT DISTINCT customer_id
      FROM dbo.vw_customer_product
      WHERE product_type = 'Savings') s
WHERE NOT EXISTS (SELECT 1 FROM dbo.vw_customer_product c
                  WHERE c.customer_id = s.customer_id
                    AND c.product_type = 'Credit Card');

-- Q7b. The list
SELECT cu.customer_id, cu.customer_number, cu.firstname, cu.lastname
FROM (SELECT DISTINCT customer_id
      FROM dbo.vw_customer_product
      WHERE product_type = 'Savings') s
JOIN dbo.dim_customer cu ON cu.customer_id = s.customer_id
WHERE NOT EXISTS (SELECT 1 FROM dbo.vw_customer_product c
                  WHERE c.customer_id = s.customer_id
                    AND c.product_type = 'Credit Card')
ORDER BY cu.customer_id;


-- Q8. Proportion of Credit Card accounts within 90% of their credit limit
-- Definition: account_balance >= 90% of credit_limit (balance = amount
-- used on the card). Accounts without a positive credit limit are left out.
SELECT
    COUNT(*) AS credit_card_accounts,
    SUM(CASE WHEN account_balance >= credit_limit * 0.9 THEN 1 ELSE 0 END) AS within_90_pct,
    CAST(SUM(CASE WHEN account_balance >= credit_limit * 0.9 THEN 1 ELSE 0 END) * 100.0
         / COUNT(*) AS DECIMAL(5,2)) AS pct_within_90
FROM dbo.vw_account_snapshot
WHERE product_type = 'Credit Card'
  AND credit_limit > 0
  AND account_balance IS NOT NULL;


/* =========================================================================
   TRANSACTIONS
   ========================================================================= */

-- Q9. Total transaction value by month, split by transaction type
-- Definition: value = SUM(ABS(amount)), so that deposits and withdrawals
-- (which may be stored with opposite signs) do not cancel each other out.
-- Q9a. Month by month
SELECT
    dt.event_year,
    dt.event_month,
    tr.transaction_type,
    COUNT(*)              AS txn_count,
    SUM(ABS(f.amount))    AS total_value
FROM dbo.dim_fact f
JOIN dbo.dim_dates       dt ON dt.dates_id       = f.dates_id
JOIN dbo.dim_transaction tr ON tr.transaction_id = f.transaction_id
JOIN dbo.dim_event       ev ON ev.event_id       = f.event_id
WHERE ev.event_type = 'Transaction'
GROUP BY dt.event_year, dt.event_month, tr.transaction_type
ORDER BY dt.event_year, dt.event_month, tr.transaction_type;

-- Q9b. Seasonality: the same figures grouped by calendar month across all
-- years. Compare avg_value_per_year across months: a month that is
-- consistently higher (e.g. December) is a seasonal peak.
SELECT
    dt.event_month,
    COUNT(*)                                    AS txn_count,
    SUM(ABS(f.amount))                          AS total_value,
    COUNT(DISTINCT dt.event_year)               AS years_covered,
    SUM(ABS(f.amount)) / COUNT(DISTINCT dt.event_year) AS avg_value_per_year
FROM dbo.dim_fact f
JOIN dbo.dim_dates dt ON dt.dates_id = f.dates_id
JOIN dbo.dim_event ev ON ev.event_id = f.event_id
WHERE ev.event_type = 'Transaction'
GROUP BY dt.event_month
ORDER BY dt.event_month;


-- Q10. Channel with the most transactions vs channel with the highest value
SELECT
    channel,
    txn_count,
    total_value,
    CAST(total_value * 1.0 / txn_count AS DECIMAL(12,2)) AS avg_value_per_txn,
    RANK() OVER (ORDER BY txn_count DESC)   AS rank_by_count,
    RANK() OVER (ORDER BY total_value DESC) AS rank_by_value
FROM (
    SELECT tr.channel,
           COUNT(*)           AS txn_count,
           SUM(ABS(f.amount)) AS total_value
    FROM dbo.dim_fact f
    JOIN dbo.dim_transaction tr ON tr.transaction_id = f.transaction_id
    JOIN dbo.dim_event ev ON ev.event_id = f.event_id
    WHERE ev.event_type = 'Transaction'
    GROUP BY tr.channel
) c
ORDER BY rank_by_count;
-- If rank_by_count and rank_by_value are different channels, the channel
-- with the most rows handles many small transactions (e.g. card taps)
-- while the other handles fewer, larger ones (see avg_value_per_txn).


-- Q11. Active vs not-active customers
-- Definition: ACTIVE = at least one Transaction or CRM Interaction within
-- 90 days of the latest date in the data (90 days is a common banking
-- rule of thumb for "recently used"). Customers with no such event at
-- all are 'Not active'.
SELECT
    activity_status,
    COUNT(*) AS customer_count,
    CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS pct_of_customers
FROM (
    SELECT
        cu.customer_id,
        CASE WHEN la.last_activity_date IS NOT NULL
              AND DATEDIFF(DAY, la.last_activity_date, ld.latest_date) <= 90
             THEN 'Active' ELSE 'Not active' END AS activity_status
    FROM dbo.dim_customer cu
    CROSS JOIN dbo.vw_latest_date ld
    LEFT JOIN dbo.vw_customer_last_activity la ON la.customer_id = cu.customer_id
) x
GROUP BY activity_status;


-- Q12. Top 20 customers by total transaction value, last 12 months of data
-- Reference point = the latest TRANSACTION date in the data (as the
-- question asks), not today's date.
SELECT TOP 20
    cu.customer_id, cu.customer_number, cu.firstname, cu.lastname,
    SUM(ABS(f.amount)) AS total_transaction_value
FROM dbo.dim_fact f
JOIN dbo.dim_customer cu ON cu.customer_id = f.customer_id
JOIN dbo.dim_dates    dt ON dt.dates_id    = f.dates_id
JOIN dbo.dim_event    ev ON ev.event_id    = f.event_id
CROSS JOIN dbo.vw_latest_txn_date lt
WHERE ev.event_type = 'Transaction'
  AND dt.event_date > DATEADD(MONTH, -12, lt.latest_txn_date)
GROUP BY cu.customer_id, cu.customer_number, cu.firstname, cu.lastname
ORDER BY total_transaction_value DESC;


/* =========================================================================
   CRM / ENGAGEMENT
   ========================================================================= */

-- Q13. Average interactions per customer, by interaction type
-- Two readings are shown:
--   avg_per_customer_with_type = total / customers who had that type
--   avg_per_all_customers      = total / ALL customers in the bank
SELECT
    it.interaction_type,
    COUNT(*)                      AS total_interactions,
    COUNT(DISTINCT f.customer_id) AS customers_with_this_type,
    CAST(COUNT(*) * 1.0 / COUNT(DISTINCT f.customer_id) AS DECIMAL(6,2)) AS avg_per_customer_with_type,
    CAST(COUNT(*) * 1.0 / (SELECT COUNT(*) FROM dbo.dim_customer) AS DECIMAL(6,2)) AS avg_per_all_customers
FROM dbo.dim_fact f
JOIN dbo.dim_interaction it ON it.interaction_id = f.interaction_id
JOIN dbo.dim_event       ev ON ev.event_id       = f.event_id
WHERE ev.event_type = 'CRM Interaction'
GROUP BY it.interaction_type
ORDER BY total_interactions DESC;


-- Q14. Channel most used for complaints vs other interaction types
-- (channel lives in dim_transaction in this model, following the drawio plan)
SELECT
    channel,
    complaints,
    other_interactions,
    CAST(complaints * 100.0 / NULLIF(SUM(complaints) OVER (), 0)         AS DECIMAL(5,2)) AS pct_of_all_complaints,
    CAST(other_interactions * 100.0 / NULLIF(SUM(other_interactions) OVER (), 0) AS DECIMAL(5,2)) AS pct_of_other_interactions
FROM (
    SELECT
        tr.channel,
        SUM(CASE WHEN it.interaction_type =  'Complaint' THEN 1 ELSE 0 END) AS complaints,
        SUM(CASE WHEN it.interaction_type <> 'Complaint' THEN 1 ELSE 0 END) AS other_interactions
    FROM dbo.dim_fact f
    JOIN dbo.dim_interaction it ON it.interaction_id = f.interaction_id
    JOIN dbo.dim_transaction tr ON tr.transaction_id = f.transaction_id
    JOIN dbo.dim_event       ev ON ev.event_id       = f.event_id
    WHERE ev.event_type = 'CRM Interaction'
    GROUP BY tr.channel
) c
ORDER BY complaints DESC;


-- Q15. Resolution rate (resolved_flag = 'Y') by channel
-- 'Unknown' flags are left out because they are not a real answer.
-- margin_of_error_pct is the usual 95% margin for a percentage:
--   1.96 * sqrt( p * (1 - p) / n ). If the lowest channel's rate is
--   within the margins of the others, the gap could just be noise;
--   a small total_interactions makes the margin wide.
SELECT
    channel,
    total_interactions,
    resolved_count,
    CAST(resolved_count * 100.0 / total_interactions AS DECIMAL(5,2)) AS resolution_rate_pct,
    CAST(196.0 * SQRT((resolved_count * 1.0 / total_interactions)
                    * (1 - resolved_count * 1.0 / total_interactions)
                    / total_interactions) AS DECIMAL(5,2)) AS margin_of_error_pct
FROM (
    SELECT
        tr.channel,
        COUNT(*) AS total_interactions,
        SUM(CASE WHEN it.resolved_flag = 'Y' THEN 1 ELSE 0 END) AS resolved_count
    FROM dbo.dim_fact f
    JOIN dbo.dim_interaction it ON it.interaction_id = f.interaction_id
    JOIN dbo.dim_transaction tr ON tr.transaction_id = f.transaction_id
    JOIN dbo.dim_event       ev ON ev.event_id       = f.event_id
    WHERE ev.event_type = 'CRM Interaction'
      AND it.resolved_flag IN ('Y', 'N')
    GROUP BY tr.channel
) c
ORDER BY resolution_rate_pct ASC;


/* =========================================================================
   COMBINED / SEGMENTATION
   ========================================================================= */

-- Q16. Value tiers by transaction activity
-- Method: quartiles. Customers with transactions are ranked by total
-- transaction value (SUM of ABS(amount)) and split into 4 equal groups.
-- Customers with no transactions get their own 'No transactions' tier,
-- so the tiers add up to all customers.
;WITH customer_value AS (
    SELECT f.customer_id, SUM(ABS(f.amount)) AS total_value
    FROM dbo.dim_fact f
    JOIN dbo.dim_event ev ON ev.event_id = f.event_id
    WHERE ev.event_type = 'Transaction'
    GROUP BY f.customer_id
),
tiered AS (
    SELECT customer_id, total_value,
           NTILE(4) OVER (ORDER BY total_value DESC) AS tier_no
    FROM customer_value
)
SELECT value_tier, customer_count, total_transaction_value
FROM (
    SELECT
        tier_no AS sort_no,
        CASE tier_no WHEN 1 THEN 'Tier 1 - Top 25%'
                     WHEN 2 THEN 'Tier 2 - Upper-middle 25%'
                     WHEN 3 THEN 'Tier 3 - Lower-middle 25%'
                     ELSE        'Tier 4 - Bottom 25%' END AS value_tier,
        COUNT(*)         AS customer_count,
        SUM(total_value) AS total_transaction_value
    FROM tiered
    GROUP BY tier_no

    UNION ALL

    SELECT 5, 'No transactions', COUNT(*), 0
    FROM dbo.dim_customer
    WHERE customer_id NOT IN (SELECT customer_id FROM customer_value)
) t
ORDER BY sort_no;


-- Q17. Customer lifecycle segmentation
-- Definition (days are counted back from the latest date in the data):
--   New     = signed up within the last 90 days
--   Active  = not new, last activity within 90 days
--   At risk = last activity 91 to 180 days ago
--   Dormant = last activity more than 180 days ago, or no activity at all
-- Why: 90 days is about one quarter without being "new" or quiet, and
-- 180 days is about two quarters with no engagement, common early-warning
-- thresholds in banking. Activity = Transaction or CRM Interaction.
SELECT lifecycle_segment, COUNT(*) AS customer_count
FROM (
    SELECT
        cu.customer_id,
        CASE
            WHEN cs.signup_date IS NOT NULL
             AND DATEDIFF(DAY, cs.signup_date, ld.latest_date) <= 90        THEN 'New'
            WHEN la.last_activity_date IS NULL
              OR DATEDIFF(DAY, la.last_activity_date, ld.latest_date) > 180 THEN 'Dormant'
            WHEN DATEDIFF(DAY, la.last_activity_date, ld.latest_date) > 90  THEN 'At risk'
            ELSE 'Active'
        END AS lifecycle_segment
    FROM dbo.dim_customer cu
    CROSS JOIN dbo.vw_latest_date ld
    LEFT JOIN dbo.vw_customer_signup        cs ON cs.customer_id = cu.customer_id
    LEFT JOIN dbo.vw_customer_last_activity la ON la.customer_id = cu.customer_id
) x
GROUP BY lifecycle_segment
ORDER BY CASE lifecycle_segment WHEN 'New'     THEN 1
                                WHEN 'Active'  THEN 2
                                WHEN 'At risk' THEN 3
                                ELSE 4 END;


-- Q18. CRM interactions vs transaction value (grouped comparison)
-- Customers are grouped by how many CRM interactions they had.
-- avg_value_all_customers counts customers with no transactions as 0;
-- avg_value_transacting_only ignores them. If the averages rise as the
-- band rises, customers who contact the bank more also transact more
-- (more engaged, not necessarily happier).
;WITH customer_interactions AS (
    SELECT f.customer_id, COUNT(*) AS interaction_count
    FROM dbo.dim_fact f
    JOIN dbo.dim_event ev ON ev.event_id = f.event_id
    WHERE ev.event_type = 'CRM Interaction'
    GROUP BY f.customer_id
),
customer_value AS (
    SELECT f.customer_id, SUM(ABS(f.amount)) AS total_value
    FROM dbo.dim_fact f
    JOIN dbo.dim_event ev ON ev.event_id = f.event_id
    WHERE ev.event_type = 'Transaction'
    GROUP BY f.customer_id
)
SELECT
    interaction_band,
    COUNT(*) AS customer_count,
    SUM(CASE WHEN total_value IS NOT NULL THEN 1 ELSE 0 END) AS customers_who_transacted,
    AVG(ISNULL(total_value, 0)) AS avg_value_all_customers,
    AVG(total_value)            AS avg_value_transacting_only
FROM (
    SELECT
        ISNULL(ci.interaction_count, 0) AS interaction_count,
        CASE WHEN ci.interaction_count IS NULL    THEN '0'
             WHEN ci.interaction_count BETWEEN 1 AND 2 THEN '1-2'
             WHEN ci.interaction_count BETWEEN 3 AND 5 THEN '3-5'
             ELSE '6+' END AS interaction_band,
        cv.total_value
    FROM dbo.dim_customer cu
    LEFT JOIN customer_interactions ci ON ci.customer_id = cu.customer_id
    LEFT JOIN customer_value        cv ON cv.customer_id = cu.customer_id
) x
GROUP BY interaction_band
ORDER BY MIN(interaction_count);


/* =========================================================================
   STRETCH
   ========================================================================= */

-- Q19. Month-over-month retention
-- "Active in a month" = at least one Transaction or CRM Interaction dated
-- in that month. The latest month is left out because it has no
-- following month to compare with (it would show a false 0%).
;WITH monthly_active AS (
    SELECT DISTINCT
        f.customer_id,
        DATEFROMPARTS(dt.event_year, dt.event_month, 1) AS month_start
    FROM dbo.dim_fact f
    JOIN dbo.dim_dates dt ON dt.dates_id = f.dates_id
    JOIN dbo.dim_event ev ON ev.event_id = f.event_id
    WHERE ev.event_type IN ('Transaction', 'CRM Interaction')
)
SELECT
    CONVERT(VARCHAR(7), a1.month_start, 120) AS month_n,
    COUNT(a1.customer_id) AS active_in_month_n,
    COUNT(a2.customer_id) AS still_active_in_month_n_plus_1,
    CAST(COUNT(a2.customer_id) * 100.0 / COUNT(a1.customer_id) AS DECIMAL(5,2)) AS retention_pct
FROM monthly_active a1
LEFT JOIN monthly_active a2
       ON a2.customer_id = a1.customer_id
      AND a2.month_start = DATEADD(MONTH, 1, a1.month_start)
WHERE a1.month_start < (SELECT MAX(month_start) FROM monthly_active)
GROUP BY a1.month_start
ORDER BY a1.month_start;


-- Q20. Accounts with an unusual transaction (spike vs the account's own history)
-- Method: for each account with at least 5 transactions, work out the
-- average and standard deviation of its own transaction sizes, then flag
-- any transaction more than 2 standard deviations above that average.
-- z_score = how many standard deviations above the account's average.
;WITH account_txn AS (
    SELECT ac.account_number, f.UniqueID, f.amount, dt.event_date
    FROM dbo.dim_fact f
    JOIN dbo.dim_account ac ON ac.account_id = f.account_id
    JOIN dbo.dim_dates   dt ON dt.dates_id   = f.dates_id
    JOIN dbo.dim_event   ev ON ev.event_id   = f.event_id
    WHERE ev.event_type = 'Transaction'
      AND ac.account_number <> 'Unknown'
),
account_stats AS (
    SELECT account_number,
           COUNT(*)           AS txn_count,
           AVG(ABS(amount))   AS avg_amount,
           STDEV(ABS(amount)) AS stdev_amount
    FROM account_txn
    GROUP BY account_number
    HAVING COUNT(*) >= 5
)
SELECT
    t.account_number, t.event_date, t.amount,
    s.txn_count,
    CAST(s.avg_amount   AS DECIMAL(12,2)) AS avg_amount,
    CAST(s.stdev_amount AS DECIMAL(12,2)) AS stdev_amount,
    CAST((ABS(t.amount) - s.avg_amount) / s.stdev_amount AS DECIMAL(6,2)) AS z_score
FROM account_txn t
JOIN account_stats s ON s.account_number = t.account_number
WHERE s.stdev_amount > 0
  AND ABS(t.amount) > s.avg_amount + 2 * s.stdev_amount
ORDER BY z_score DESC;
