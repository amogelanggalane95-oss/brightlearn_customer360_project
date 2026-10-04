-- The fact table is rebuilt on every run (only drop it if it exists,
-- so the very first run does not fail)
IF OBJECT_ID('dbo.dim_fact', 'U') IS NOT NULL
    DROP TABLE dbo.dim_fact;

CREATE TABLE dbo.dim_fact (
    UniqueID         INT IDENTITY(1,1) PRIMARY KEY,
    customer_id      INT FOREIGN KEY REFERENCES dbo.dim_customer(customer_id),
    contact_id       INT FOREIGN KEY REFERENCES dbo.dim_customer_contact(contact_id),
    account_id       INT FOREIGN KEY REFERENCES dbo.dim_account(account_id),
    location_id      INT FOREIGN KEY REFERENCES dbo.dim_location(location_id),
    transaction_id   INT FOREIGN KEY REFERENCES dbo.dim_transaction(transaction_id),
    interaction_id   INT FOREIGN KEY REFERENCES dbo.dim_interaction(interaction_id),
    dates_id         INT FOREIGN KEY REFERENCES dbo.dim_dates(dates_id),
    event_id         INT FOREIGN KEY REFERENCES dbo.dim_event(event_id),
    account_balance  DECIMAL(12,2),
    amount           DECIMAL(12,2),
    credit_limit     DECIMAL(12,2),
    loan_amount      DECIMAL(12,2)
);
GO


-- dim_fact: one row per (distinct) staging row, pointing at every dimension
IF NOT EXISTS (SELECT 1 FROM dbo.dim_fact)
BEGIN
    INSERT INTO dbo.dim_fact
        (customer_id, contact_id, account_id, location_id,
         transaction_id, interaction_id, dates_id, event_id,
         account_balance, amount, credit_limit, loan_amount)
    SELECT DISTINCT
        cu.customer_id, co.contact_id, ac.account_id, lo.location_id,
        tr.transaction_id, it.interaction_id, da.dates_id, ev.event_id,
        v.account_balance, v.amount, v.credit_limit, v.loan_amount
    FROM dbo.vw_clean_activity v
    JOIN dbo.dim_customer         cu ON cu.customer_number  = v.client_number
    JOIN dbo.dim_customer_contact co ON co.email            = v.email
                                    AND co.mobile_number    = v.mobile_number
    JOIN dbo.dim_account          ac ON ac.account_number   = v.account_number
    JOIN dbo.dim_location         lo ON lo.province         = v.province
                                    AND lo.city             = v.city
    JOIN dbo.dim_transaction      tr ON tr.transaction_type = v.transaction_type
                                    AND tr.channel          = v.channel
    JOIN dbo.dim_interaction      it ON it.interaction_type = v.interaction_type
                                    AND it.resolved_flag    = v.resolved_flag
    JOIN dbo.dim_dates            da ON da.signup_date      = v.signup_date
                                    AND da.event_date       = v.event_date
    JOIN dbo.dim_event            ev ON ev.event_type       = v.event_type;
END
GO