# How to Run the Customer 360 Pipeline End to End

This guide explains how to run the whole project from an empty SQL Server to a finished warehouse and the answers to the 20 business questions.

## What the pipeline does

```
raw rows  ->  staging  ->  split by event type  ->  clean view  ->  dimensions  ->  fact table  ->  validation  ->  questions
(INSERTs)   (stg_Customer360)   (SSIS)             (vw_clean_activity)  (dim_*)      (dim_fact)      (checks)     (Q1-Q20)
```

Two databases are used:

| Database | Purpose |
|---|---|
| `stg_Customer360` | Staging. A raw, all-text copy of the extract (21,500 rows) plus three split tables, one per event type |
| `dwh_Customer360` | The star schema: 8 dimension tables, the fact table `dim_fact`, a cleaning view and helper views |

## What you need

- SQL Server (Developer or Express) and SQL Server Management Studio (SSMS)
- Visual Studio with the SQL Server Integration Services (SSIS) extension
- Permission to create databases (normal on your own machine)
- The project files:

| File | What it is |
|---|---|
| `0_0_customer360_full_code.sql` (or `customer360_full_code_with_instructions.sql`) | The full script: staging load, warehouse build, validation, helper views and the 20 questions |
| `ssis_task_scripts.sql` | The same warehouse SQL split into one section per SSIS task |
| SSIS project / `.dtsx` package | The package that runs the split, the dimension and fact loads and the validation |

## Before you start

1. Open SSMS and connect to your SQL Server using Windows Authentication.
2. Set **Query > Results To > Results to Grid**.
3. Decide whether this is a **fresh start**. The staging load can only be run once (see "Starting over" below).

---

## Step 1: Create staging and load the raw rows (SSMS, run once)

Open the script in SSMS. Highlight and run each part in order:

1. **Create staging.** From the top of the script down to the first `GO`. This creates `stg_Customer360` and the table `customer_activity` (every column is text, so nothing can be rejected on load).
2. **Load the rows.** All the `INSERT ... VALUES` blocks, down to the last `GO` before `IF DB_ID('dwh_Customer360')`. This takes about a minute.
3. **Create the warehouse database.** The `IF DB_ID('dwh_Customer360')...` lines and `USE dwh_Customer360;`.
4. **Check staging.** Run the two `SELECT` lines under "Sanity check on staging".

**Expected result:** `rows_loaded = 21500`, with a count for each of the three event types (Product Enrollment, CRM Interaction, Transaction). If the number is wrong, stop and see "Starting over".

---

## Step 2: Run the SSIS package

Open the SSIS project in Visual Studio, then press **Start** (or right-click the package and choose **Execute Package**). The package runs these tasks in order, each one only after the previous one succeeds:

| # | Task | Type | What it does |
|---|---|---|---|
| 1 | Prepare split tables | Execute SQL | Creates `stg_enrollment`, `stg_interaction` and `stg_transaction` if missing, then empties them so the package can be re-run |
| 2 | Split events | Data Flow | Reads `customer_activity`; a Conditional Split sends each row to the table for its `event_type`. Anything unexpected goes to the default output and is counted |
| 3 | Create DWH tables | Execute SQL | Creates the 8 dimension tables if missing, and drops and recreates `dim_fact` |
| 4 | Create clean view | Execute SQL | Creates `vw_clean_activity` (trims text, turns blanks into 'Unknown', converts dates and numbers with `TRY_CAST`) |
| 5 | Load dimensions | Execute SQL | Loads each dimension, inserting only rows that are not already there |
| 6 | Load fact | Execute SQL | Loads `dim_fact`, one row per distinct clean staging row, pointing at every dimension |
| 7 | Validate | Execute SQL | Fails the package if the split tables do not add up to staging, or if the fact table does not match the clean data |

**Why this order:** the dimensions must exist before the fact table, because the fact table points at them.

**Expected result:** all tasks turn green. If Task 7 turns red, the numbers do not add up, so do not continue to the questions.

> **No SSIS available?** The same logic is in the main script. Run its Steps 5 to 9 in SSMS instead: create the tables, create the clean view, load the dimensions, load the fact table, then run the validation. The result is the same warehouse.

---

## Step 3: Validate the build (SSMS)

Run the **PART 2 - VALIDATE THE BUILD** section of the script. In the first result grid, `rows_in_dwh` must equal `rows_expected` on every line. This confirms that nothing was lost or duplicated.

---

## Step 4: Create the helper views (SSMS)

Run all of **PART 3 - HELPER VIEWS**. These views give one row per customer or per account, which several questions need (for example `vw_latest_date`, which is the reference date used instead of today's date because the extract is static).

---

## Step 5: Answer the business questions (SSMS)

Run **PART 4 - BUSINESS QUESTIONS** one question at a time: highlight a single question and press F5. Copy or screenshot each result, since the project asks for the query and the result for every question.

Notes:
- Run **Q3 as one block**: it creates a temporary table that Q3a and Q3b read.
- Definitions (active customer, value tiers, lifecycle thresholds, what counts as a data quality problem) are stated in the comments above each query.
- Q20 also asks what extra data you would want to confirm fraud. That explanation goes in the write-up, since the script only has the query.

---

## Is it safe to run again?

| Part | Safe to re-run? | Why |
|---|---|---|
| Steps 3 to 6 of the script / SSIS tasks 3 to 7 | Yes | Dimensions only insert new rows, and the fact table is rebuilt each time |
| SSIS tasks 1 and 2 | Yes | The split tables are emptied first |
| Helper views and questions | Yes | Views use `CREATE OR ALTER` |
| **Step 1 (staging load)** | **No** | There is no truncate, so running it again would add the 21,500 rows a second time |

## Starting over

To rebuild everything from scratch, drop both databases in SSMS and run Step 1 again:

```sql
USE master;
IF DB_ID('dwh_Customer360') IS NOT NULL
BEGIN
    ALTER DATABASE dwh_Customer360 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE dwh_Customer360;
END
IF DB_ID('stg_Customer360') IS NOT NULL
BEGIN
    ALTER DATABASE stg_Customer360 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE stg_Customer360;
END
```

## If something goes wrong

| Problem | What to check |
|---|---|
| `rows_loaded` is not 21,500 | The staging load ran twice or only partly. Start over |
| SSIS Execute SQL Task fails on `GO` or `USE` | Those words are not allowed in Execute SQL Tasks. Use the sections in `ssis_task_scripts.sql`, which contain none |
| Task 7 (Validate) fails | A split table count or the fact count does not match. Check that the Conditional Split's default output is empty |
| Q3a or Q3b says `#monthly_signups` is invalid | Run all of Q3 together in the same query window |
| "Invalid object name" on a `dim_` table or view | The wrong database is active. Check that the toolbar says `dwh_Customer360` |

## Running it on a schedule (optional)

The brief does not require automation. In a real setting, the SSIS package could be deployed and scheduled nightly with SQL Server Agent (not available in Express edition), but that is outside the scope of this project.

## Deliverables produced by a full run

- Staging database `stg_Customer360` and warehouse database `dwh_Customer360`
- The SSIS package, with a screenshot of a successful run
- Validation output showing matching row counts
- Results for Q1 to Q20
