# Customer 360: How I Built It, and Why the Code Looks the Way It Does

**Author:** Amogelang
**Project:** Customer 360 data warehouse (SQL Server)
**Final deliverable:** one SQL script that builds staging, builds the warehouse, validates it, and answers all 20 business questions.

This document is the story behind the code. The README tells you *what* was asked. This tells you *what actually happened*: where I got stuck, what I tried, what worked, and why each decision mattered.

---

## 1. The short version

The brief expected me to load `activity_extract.csv` into SQL Server using an SSIS Flat File Source. I could not get the CSV to load, so I changed the approach:

1. I first planned the model in Excel, grouping related columns by colour, and drew it up in draw.io (section 4).
2. I put the raw rows into a staging table myself, using `INSERT ... VALUES`.
3. I kept every staging column as text, so nothing could be rejected on load.
4. I cleaned the data in a **view**, not in the staging table.
5. I built the star schema from that clean view, using plain SQL.
6. I checked every table against the expected row counts.
7. I answered the 20 questions against the warehouse tables only.

Everything below explains why.

---

## 2. Challenge 1: The CSV would not load

**What was supposed to happen:** import the CSV as a flat file, straight into a table.

**What happened:** SSMS would not accept the file. The CSV had too many problems for the import to cope with: inconsistent formats, blanks, stray spaces, mixed casing and so on. When an import fails on one bad field, you cannot easily see which field or why.

**What I did instead:** I converted the rows into `INSERT INTO ... VALUES (...)` statements and loaded them into the staging table myself. The staging load ran successfully and I confirmed the row count (21,500 rows).

**Why it mattered:** this decision shaped the whole project. Because the import tool was not cleaning anything for me, *all* the cleaning had to happen in SQL, which is why the project ended up as pure SQL with no SSIS and no Python.

**Trade-off I accept:** the README asked for SSIS with a Conditional Split. I did not use SSIS, but I kept the same ideas: a separate staging layer, a split of the three event types, a re-runnable load, and a clear order of loading. These are done in SQL instead (see section 9).

---

## 3. Challenge 2: A messy file I could not trust

Once the data was in, the problems became visible. Looking at the rows, I could see:

| Problem | Example in the data |
|---|---|
| Spaces around values | `' sam.de villiers82@webmail.co.za '` |
| Inconsistent casing | `AYESHA.NKOSI66@TELKOMSA.NET` next to lowercase emails |
| Phone numbers in many formats | `0652984200`, `+27675882155`, `27823081873`, `063-517-1761`, `084 152 0596` |
| Missing values | blank mobile numbers, blank gender |
| Odd category values | gender `U` instead of `M` or `F` |
| Repeated client details | name, contact and signup date repeated on every row for a client |
| Columns that only apply to some rows | credit limit only on credit cards, channel only on transactions, and so on |

**Strategy: keep staging raw, clean in a view.**

- The staging table is deliberately all `VARCHAR`. Nothing can fail on load, and staging stays an honest copy of what came in.
- The cleaning lives in one view, `vw_clean_activity`. It:
  - trims spaces (`LTRIM(RTRIM(...))`),
  - turns blanks into `NULL` and then into `'Unknown'` for text columns (`NULLIF` + `ISNULL`),
  - maps any gender that is not `M` or `F` to `'Unknown'`,
  - converts dates and numbers with `TRY_CAST`.

**Why `TRY_CAST` mattered:** a normal `CAST` stops the whole query when it meets one bad value. `TRY_CAST` returns `NULL` instead, so one bad date cannot break 21,500 rows.

**Why a view mattered:** I can change a cleaning rule in one place and everything downstream (all dimensions and the fact table) picks it up. It also means I never overwrite the raw data, so I can always go back and check what the source really said.

**Decision on bad data:** I chose to *correct or flag* rather than *delete*. Blank values become `'Unknown'`, so a customer with a missing mobile number is still counted. The README warns against "deleting anything that looked unusual", and this follows that advice. Question 4 later counts these records as data quality problems.

---

## 4. Step 0: Planning the model in Excel before writing any code

Before I wrote a single line of SQL or opened draw.io, I did my data modelling in **Excel**. This is where the design really started.

**What I did:**

1. **Laid the columns out.** I put the raw file's columns side by side in a sheet so I could see everything the source contained in one view.
2. **Worked out what is related.** I went through the columns asking "which of these describe the same thing?" For example, a client's name and date of birth describe the *person*, email and mobile number describe how to *reach* them, province and city describe *where* they are, and channel and transaction type describe the *transaction*.
3. **Colour-coded the groups.** Every group of related columns got its own colour, so columns that belong together shared a colour and I could see the groups at a glance.
4. **Took the groups into draw.io.** I used those coloured groups to draw the data architecture (the star schema) in draw.io. Each group of related columns became a dimension table, and the numbers (`amount`, `account_balance`, `credit_limit`, `loan_amount`) went into the central fact table.
5. **Only then wrote the code.** The DDL in the script follows the draw.io diagram.

**Why this was significant for me:**

- The raw file is one wide, flat table. It is hard to know where to cut it into tables just by staring at the columns. Colouring them made the natural groups obvious and stopped me guessing.
- It meant the design came from looking at the data, not from whichever join happened to work first. That is exactly what the README's "Modelling judgment" criterion asks for.
- Planning on paper first meant fewer rebuilds later. When I coded, I already knew which dimensions I needed and which columns belonged to each.
- It gave me something visual to check the finished code against. The draw.io diagram and the tables in the script match.

I chose Excel because it is a tool I am comfortable with, and as a beginner that let me focus on understanding the data rather than fighting new software.

---

## 5. Challenge 3: Designing the model from one flat table

The raw data is one big table where every row is an event: a product enrollment, a CRM interaction, or a transaction. I had to split it into proper tables.

**My plan (drawn in draw.io first):** a star schema with one central table, `dim_fact`, linked to eight dimensions:

`dim_customer`, `dim_customer_contact`, `dim_location`, `dim_interaction`, `dim_event`, `dim_account`, `dim_transaction`, `dim_dates`

**Design choices and why:**

- **Surrogate keys with `IDENTITY(1,1)`.** The source gives no ready-made IDs for most things, so each dimension gets its own generated key.
- **Customer and contact are separate.** The customer's identity (name, date of birth, gender) is separate from their contact details (email, mobile), so a contact change does not touch the customer record.
- **`dim_event` tells the three event types apart.** This is how I "split" the single file. Instead of three physical copies of the data, every fact row carries an `event_id` saying whether it is an enrollment, interaction or transaction.
- **One fact table.** `dim_fact` has one row per event (one row per distinct cleaned staging row). It holds the numbers (`amount`, `account_balance`, `credit_limit`, `loan_amount`) and a key to each dimension. Columns that do not apply to a row type are simply empty for that row.

I stuck with my original plan and kept the design simple because I am a beginner and wanted SQL I could fully understand and explain.

---

## 6. Challenge 4: Making the load safe to run again

I ran the script many times while building it, so it had to be re-runnable without creating duplicates.

**Strategies:**

- **Create-if-missing.** Dimension tables use `IF OBJECT_ID(...) IS NULL CREATE TABLE ...` and databases use `IF DB_ID(...) IS NULL`.
- **Insert-only-new.** Each dimension load uses `WHERE NOT EXISTS (...)`, so a value that is already there is not inserted again.
- **Rebuild the fact table.** The fact table is dropped if it exists and recreated on every run. The README accepts truncate-and-reload for this exercise.
- **Guard on the fact load.** The fact insert only runs if the fact table is empty (`IF NOT EXISTS (SELECT 1 FROM dbo.dim_fact)`).

**Why it mattered:** without these, every re-run would have doubled my row counts and quietly broken every answer. A load that can be repeated safely is the difference between a script and a one-off experiment.

---

## 7. Challenge 5: The tricky parts inside the data

### 6.1 Account status only exists on one kind of row
Only enrollment rows carry the account status. Transactions and CRM rows do not. So `dim_account` is loaded in two steps:

1. First, accounts from `Product Enrollment` rows (they carry the real status).
2. Then, any account that never had an enrollment row, and the `'Unknown'` account used by CRM rows with no account, gets status `'Unknown'`.

### 6.2 Duplicate rows
The fact load uses `SELECT DISTINCT`, so exact duplicate rows in the source do not become duplicate facts. The validation step compares the fact count against `SELECT DISTINCT *` on the clean view so I can prove it.

### 6.3 Joins that multiply rows
Joining many tables can silently inflate counts if a dimension has two matching rows. The README specifically warns about "double counted transactions from a bad join". To protect against this:
- every dimension is built to have one row per natural key (for example, one row per `customer_number`),
- the validation query checks each dimension count against the expected distinct count.

### 6.4 One customer, many facts: helper views
Many questions need "one row per customer" or "one row per account", but the fact table has many rows per customer. I built small helper views so each question stays simple:

| View | What it gives me |
|---|---|
| `vw_customer_location` | one province and city per customer |
| `vw_customer_signup` | one signup date per customer |
| `vw_latest_date` | the latest event date in the data |
| `vw_latest_txn_date` | the latest transaction date (needed for Q12) |
| `vw_customer_last_activity` | each customer's latest transaction or CRM date |
| `vw_customer_product` | one row per customer per product held |
| `vw_account_snapshot` | one row per account, its most recent enrollment record, picked with `ROW_NUMBER()` |

**Why it mattered:** without `vw_account_snapshot`, an account with two enrollment records would be counted twice in balance totals (Q6) and credit card limits (Q8).

### 6.5 "Today" does not exist in a static file
Questions like "last 12 months" and "active customer" need a reference date. Using `GETDATE()` would make every customer look dormant, because the data is a fixed extract. I used the **latest date in the data** instead (`vw_latest_date` and `vw_latest_txn_date`), which is also what Q12 explicitly asks for.

### 6.6 Spelling of category values
The questions rely on exact spellings (`'Transaction'`, `'CRM Interaction'`, `'Savings'`, `'Credit Card'`, `'Complaint'`, `'Y'`/`'N'`). I added a small query that lists every distinct value in each category column, so I can confirm the spellings before trusting any answer.

---

## 8. Challenge 6: Proving the build is correct

I did not want to just *hope* the warehouse was right. Part 2 of the script is a validation step:

- It lists each table with `rows_in_dwh` next to `rows_expected`. The two numbers should match on every line.
- It joins the fact table back to the dimensions (`SELECT TOP 20 ...`) to prove the split can be put back together.
- It checks the staging row count (expected 21,500) and the count per event type before anything else runs.

**Why it mattered:** these checks catch a bad join or a missed insert straight away, before I build 20 queries on top of it.

---

## 9. How my approach maps to the README requirements

| README asks for | What I did instead / how I covered it |
|---|---|
| SSIS Flat File Source | Flat file import failed, so I loaded staging with `INSERT ... VALUES` |
| Staging layer separate from the model | `stg_Customer360` (staging) and `dwh_Customer360` (warehouse) are separate databases |
| Conditional Split into event types | `dim_event` plus the `event_type` filters in views and queries |
| Type conversion, whitespace and casing cleanup, invalid values | `vw_clean_activity` using `TRIM`, `NULLIF`, `ISNULL`, `TRY_CAST` |
| Correct load order | dimensions are loaded first, then the fact table that points at them |
| Re-runnable without duplicates | create-if-missing, `NOT EXISTS`, fact rebuild |
| Date dimension | `dim_dates` with year and month |
| Dimensions for client, product | `dim_customer`, `dim_account` (product type lives here) |
| ERD in draw.io | planned in Excel (related columns grouped by colour), then drawn in draw.io before the code; the code follows it |
| SQL answers to all questions | Part 4 of the script, Q1 to Q20 |

Where I differ (no SSIS, a single fact table) I am being upfront about it rather than hiding it.

---

## 10. The last stretch: one script, 20 answers

By the end the DWH code was working well. The only thing left was the 20 questions. I:

1. Wrote a draft of the answers (Q1 to Q20).
2. Compared the draft against `questions.md` to make sure every question was covered and any needed definition was stated.
3. Merged the warehouse build and the answers into **one single script**, so the whole project can be run from top to bottom.

For questions that ask me to define a term (active customer, value tiers, lifecycle segments, data quality problem), I state the definition and the reason in a comment above the query.

---

## 11. What I learned

- **Raw data is never as clean as the brief suggests.** Profiling first saved me from building on bad assumptions.
- **Keep raw and clean separate.** All-text staging plus a cleaning view meant I could fix rules without reloading anything.
- **Beginner-friendly SQL is a strength.** Short, readable steps (a view, then a dimension, then the fact) were easier to test than one huge query.
- **Validation is not optional.** Row-count checks caught problems early.
- **When a tool fails, change the route, not the goal.** The flat file import failed, but the goal (a clean star schema that answers the business questions) stayed the same.

---

## 12. How to run it

1. Open `0_0_customer360_full_code.sql` in SSMS.
2. Run it from top to bottom. It creates `stg_Customer360` and `dwh_Customer360` if they do not exist, loads staging, builds the dimensions and fact table, validates the build, and then runs the 20 questions.
3. Check the validation output: `rows_in_dwh` should equal `rows_expected` on every line.
4. Re-running is safe. Dimensions only add new rows and the fact table is rebuilt.

---

## 13. Known limitations (honest notes)

- **No SSIS.** See section 2.
- **One combined fact table** instead of separate facts for transactions and interactions. The grain is *one row per event*, so numeric columns that do not apply to an event type are empty.
- **`dim_dates` is a distinct signup-date and event-date pair**, not a full calendar table, so dates with no activity do not appear.
- **Client history is not tracked** (effectively SCD Type 1): a customer has one current row in `dim_customer`.
- **Staging was loaded by hand** from converted CSV rows, so it is not a repeatable file import.
