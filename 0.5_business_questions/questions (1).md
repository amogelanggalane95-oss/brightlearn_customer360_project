# Business Questions

Answer every question below using SQL run against your `dw` dimensional
model, not the raw or staging tables. Include the query and the result for
each. Where a question asks you to define a business term (e.g. "active",
"high value"), state the definition you chose and why, before answering.

## Customer base

1. How many customers does the bank have per province, and what share of
   the total does each province represent?
2. What is the age distribution of the customer base? Present it in age
   bands of your own choosing and justify the bands.
3. How many customers have signed up per month over the last two years?
   Is signup growth trending up, flat, or down?
4. How many customer records look like data quality problems (e.g. missing
   contact details, duplicate identity)? Report the count and what you
   count as a "problem".

## Products

5. How many customers hold each product type, and how many hold more than
   one product (cross-holding)?
6. What is the total and average account balance by product type?
7. Which customers hold a Savings account but no Credit Card? Report the
   count, this is a cross-sell list.
8. What proportion of Credit Card accounts are within 90% of their credit
   limit?

## Transactions

9. What is total transaction value by month, split by transaction type?
   Are there seasonal patterns?
10. Which transaction channel handles the most transactions, and which
    handles the highest total value? (These may not be the same channel,
    explain why, if so.)
11. Define "active customer" using transaction and/or interaction recency,
    state your definition, and report how many customers are active vs not,
    as of the latest date in the data.
12. Who are the top 20 customers by total transaction value in the last 12
    months of data? (Use the latest transaction date in the data as your
    reference point, not today's date, this is a static extract.)

## CRM / engagement

13. What is the average number of interactions per customer, split by
    interaction type?
14. Which channel is most used for complaints specifically, versus other
    interaction types?
15. What is the resolution rate (`resolved_flag = Y`) by channel? Which
    channel resolves the least, and could that be sample-size noise rather
    than a real difference?

## Combined / segmentation

16. Segment customers into a small number of value tiers based on
    transaction activity (your choice of method, quartiles, fixed
    thresholds, etc.). Report the customer count and total transaction
    value per tier.
17. Build a simple customer lifecycle segmentation (e.g. New / Active / At
    risk / Dormant) using signup date and activity recency. State your
    thresholds and justify them. Report the customer count per segment.
18. Is there a relationship between number of CRM interactions and
    transaction value? (A simple grouped comparison is enough, this is not
    a statistics course.)

## Stretch (optional, for interns who finish early)

19. Build a month-over-month retention view: of customers active in month
    N, what percentage were still active in month N+1?
20. Identify accounts with unusual transaction patterns (e.g. a sudden
    spike relative to the account's own history) and explain what
    additional data you'd want to confirm whether it's fraud.
