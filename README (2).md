# Customer360 Data Warehouse (SQL Server + SSIS)

> One messy customer file in. One clean star schema and 20 answered business questions out. **SQL only, no Python.**

---

## 1. The story in one minute

A bank has a single flat file that mixes everything about its customers: who they are, where they live, the accounts they hold, the transactions they make and the times they phoned or emailed the bank. It is one row per event, 21,500 rows in total, and it is hard to answer simple questions from it.

This project takes that flat file and turns it into a **Customer 360 data warehouse**: a tidy star schema where each fact lives in exactly one place. On top of it sit **20 business questions** (customer base, products, transactions, CRM engagement, segmentation) answered with plain SQL against the warehouse, never against the raw data.

The whole thing is automated by an **SSIS package**, so the entire pipeline runs in order with one click.

---

## 2. The challenges, the strategy, and why it mattered

| # | Challenge | What I did | Why it mattered |
|---|-----------|-----------|-----------------|
| 1 | The CSV would not load as a flat file in SSMS. Too many problems in the file. | Loaded the rows myself with `INSERT ... VALUES`, in batches of 1,000 rows separated by `GO`. | Got every row in reliably instead of fighting the import wizard. Batching keeps each statement a manageable size. |
| 2 | I did not want to guess how to split the data. | Modelled it in **Excel** first: looked at every column, worked out which ones are related, and colour-grouped them. Then drew the architecture in **draw.io** before writing any code. | The plan came first, so the code simply follows the picture. |
| 3 | Dirty text data (blank values, spaces, mobile numbers like `+27...`, dates stored as text). | Staging keeps **everything as text** (`VARCHAR`). Cleaning happens later, in one view (`vw_clean_activity`) that trims text, turns blanks into `'Unknown'` and converts to real `DATE` / `DECIMAL`. | Staging never rejects a row. All cleaning rules live in one place. |
| 4 | Scripts must be safe to rerun. | Databases and tables are only created if they do not already exist, and the fact table is dropped and rebuilt each run. | A rerun gives the same result and never fails on the first run. |
| 5 | Ambiguous business words like "active" or "high value". | Every question states its **definition** in a comment above the query (for example, active = a transaction or CRM interaction in the last 90 days). | Anyone reading the answer knows exactly what was counted. |
| 6 | The data is a static extract, so `GETDATE()` would give wrong answers. | Created `vw_latest_date`, where "today" is the latest date in the data. | Age, "last 90 days" and "last 12 months" are all measured fairly. |

---

## 3. The architecture

The pipeline has two databases: a **staging** database that holds the raw data exactly as it arrived, and a **warehouse** database that holds the cleaned, split data.

```
 raw data (21,500 rows)
        |
        v
 stg_Customer360          <- staging: one flat, unsplit table (customer_activity)
        |
        |  clean (vw_clean_activity) + split into dimensions
        v
 dwh_Customer360          <- warehouse: star schema (dim_fact + 8 dimensions)
        |
        v
 Helper views  ->  20 business questions
```

### The star schema

I planned the model in Excel, then drew it in draw.io:

![Customer360 star schema](images/star_schema.png)

At the centre is **`dim_fact`**. It holds the numbers (`account_balance`, `amount`, `credit_limit`, `loan_amount`) and one key for each of the eight dimensions around it:

| Dimension | What it describes |
|-----------|-------------------|
| `dim_customer` | Who the customer is: customer number, name, date of birth, gender |
| `dim_customer_contact` | Email and mobile number |
| `dim_location` | Province and city |
| `dim_account` | Account number, status and product type |
| `dim_transaction` | Transaction type and channel |
| `dim_interaction` | CRM interaction type and whether it was resolved |
| `dim_event` | The kind of event: Transaction, CRM Interaction or Product Enrollment |
| `dim_dates` | Signup date and event date (plus year and month) |

> The drawio plan stayed my guide throughout, with small additions: `event_year` and `event_month` on `dim_dates`.

---

## 4. The SSIS pipeline

The last piece of the project is the SSIS package (`Package.dtsx`). It is a chain of **Execute SQL Tasks**, one per stage, joined by green precedence arrows. A task only starts when the one before it has succeeded, so the pipeline always runs in the right order.

### Phase 1: build and load staging

![SSIS phase 1: staging](images/ssis_phase1_staging.png)

1. **`create_stg_customer360`**: creates the staging database if it is missing.
2. **`create_stg_tables`**: creates the flat `customer_activity` table, with every column as text.
3. **`loading_data_into_stg_table`**: runs the `INSERT ... VALUES` batches that load all 21,500 rows.

### Phase 2: build and fill the warehouse

![SSIS phase 2: warehouse](images/ssis_phase2_warehouse.png)

4. **`create_dwh_database`**: creates the warehouse database if it is missing.
5. **`creating_dwh_tables`**: creates the eight dimensions and the fact table.
6. **`splitting_dwh_data`**: cleans the staging data and splits it into the dimensions, then builds `dim_fact`.

Green ticks on the last task of each phase show the run completed successfully.

---

## 5. How the warehouse gets built

1. **Sanity check on staging.** Confirm 21,500 rows loaded and look at the event type counts.
2. **Clean view.** `vw_clean_activity` trims text, replaces blanks with `'Unknown'` and converts text to `DATE` and `DECIMAL`.
3. **Fill the dimensions** with `SELECT DISTINCT`, one row per unique value:
   - `dim_customer`: one row per customer number
   - `dim_account`: accounts from *Product Enrollment* rows first (only they carry the account status), then any account without an enrollment row is added with status `'Unknown'`
   - the rest: one row per unique combination (province + city, email + mobile, and so on)
4. **Fill `dim_fact`.** Each cleaned staging row is matched to its dimension keys by joining back on the values.
5. **Verify.** Row counts per table, plus a join across everything to prove the split works.

---

## 6. Helper views

To keep the 20 answers short and readable, a few reusable views sit between the warehouse and the questions:

| View | Purpose |
|------|---------|
| `vw_customer_location` | One row per customer with province and city |
| `vw_customer_signup` | One row per customer with signup date |
| `vw_latest_date` | The latest date in the data (our "today") |
| `vw_latest_txn_date` | The latest *transaction* date (used for Q12) |
| `vw_customer_last_activity` | Each customer's most recent transaction or CRM interaction |
| `vw_customer_product` | One row per customer per product held |
| `vw_account_snapshot` | One row per account, its latest enrollment record (no double counting) |

---

## 7. The 20 business questions

All answers query the **dimensional model**, never staging.

**Customer base**
- **Q1** Customers per province and share of the total
- **Q2** Age distribution (bands: 18-24, 25-34, 35-44, 45-54, 55-64, 65+)
- **Q3** Signups per month over the last 24 months, and the trend (up, down or flat)
- **Q4** Data-quality problems: missing contact details and duplicate identities

**Products and accounts**
- **Q5** Customers per product type, and customers holding 2+ products
- **Q6** Total and average account balance by product type
- **Q7** Customers with a Savings account but no Credit Card (cross-sell list)
- **Q8** Share of Credit Card accounts within 90% of their credit limit

**Transactions**
- **Q9** Transaction value by month and type, plus seasonality
- **Q10** Channel with the most transactions vs the channel with the highest value
- **Q11** Active vs not-active customers
- **Q12** Top 20 customers by transaction value in the last 12 months

**CRM and engagement**
- **Q13** Average interactions per customer, by interaction type
- **Q14** Channel most used for complaints vs other interaction types
- **Q15** Resolution rate by channel, with a 95% margin of error

**Segmentation and stretch**
- **Q16** Value tiers (quartiles) by transaction activity
- **Q17** Lifecycle segments: New, Active, At risk, Dormant
- **Q18** Do customers who contact the bank more also transact more?
- **Q19** Month-over-month retention
- **Q20** Accounts with an unusual transaction (more than 2 standard deviations above the account's own average)

### Key definitions

| Term | Definition used |
|------|-----------------|
| Today | The latest `event_date` in the data (static extract) |
| Active | At least one Transaction or CRM Interaction in the last 90 days |
| New | Signed up within the last 90 days |
| At risk | Last activity 91 to 180 days ago |
| Dormant | Last activity over 180 days ago, or none at all |
| Holds a product | Has a *Product Enrollment* event for that product type |
| Transaction value | `SUM(ABS(amount))`, so deposits and withdrawals do not cancel out |

---

## 8. How to run it

1. Open SQL Server Management Studio, or run the SSIS package `Package.dtsx` (it executes the six tasks in order).
2. If running by hand, execute `customer360_full_code.sql` from top to bottom. It is one script: staging, load, warehouse build, views and the 20 answers.
3. Check the sanity query. It should report **21,500** rows in staging.

---

## 9. Files

| File | What it is |
|------|-----------|
| `customer360_full_code.sql` | The complete script: staging, load, warehouse, views and Q1-Q20 |
| `images/star_schema.png` | The star schema design |
| `images/ssis_phase1_staging.png` | SSIS control flow, staging phase |
| `images/ssis_phase2_warehouse.png` | SSIS control flow, warehouse phase |

---

## 10. What I learned

- **Plan before you code.** Excel and draw.io turned a wall of columns into a clear design.
- **Keep raw data raw.** Staging as text means nothing gets rejected, and cleaning happens in one controlled place.
- **Write your definitions down.** "Active" means nothing until you say what it means.
- **Make it rerunnable.** Scripts that survive a second run save a lot of stress.
- **When the tool fights you, change the approach.** The CSV would not load, so I loaded it a different way.
