# Subscription Data Cleaning with SQL (BigQuery)

A data cleaning project that turns a messy subscription export into an analysis-ready table using Google BigQuery SQL. The pipeline standardizes text fields, parses mixed date formats, removes duplicates and test accounts, fixes price errors, and flags remaining quality issues instead of silently dropping them.

**Tools:** Google BigQuery (Standard SQL)
**Skills demonstrated:** data profiling, string standardization, date parsing, deduplication with window functions, CTE-based pipelines, regex-based validation, rule-based data quality checks

---

## Project Overview

| | |
|---|---|
| **Input** | `subscriptions_raw.csv` (162 rows, 12 columns) |
| **Output** | `subscriptions_clean_project.csv` (147 rows, 13 columns, includes a `qc_flag` column) |
| **Script** | `Datacleaning.sql` |

### Raw Dataset Columns

`subscription_id`, `customer_id`, `customer_email`, `country`, `plan`, `monthly_price`, `status`, `start_date`, `end_date`, `payment_method`, `updated_at`, `internal_notes`

---

## Data Quality Issues Found

Profiling the raw data with `COUNT`, `GROUP BY` and `COUNTIF` queries showed the following problems:

| Issue | Example | Column(s) |
|---|---|---|
| Inconsistent casing and whitespace | `active`, ` active `, `ACTIVE` | `status`, `plan` |
| Spelling variants and typos | `Canceled` / `Cancelled`, `PAUSSED` | `status` |
| Country aliases and abbreviations | `UK`, `U.K.`, `uk`, `IE`, `DE`, `ITALY` | `country` |
| Placeholder and missing values | `NULL`, `N/A`, empty string | `payment_method`, `customer_email` |
| Mixed date formats | `2025-07-28` and `24/01/2026` | `start_date` |
| Duplicate subscriptions | 12 duplicate `subscription_id` rows (150 unique IDs in 162 rows) | `subscription_id` |
| Invalid prices | Negative values (e.g. `-19.99`) and prices stored in cents (e.g. `1999.00`) | `monthly_price` |
| Malformed emails | `liam.rossi.example.com` (no `@`) | `customer_email` |
| Test accounts | `TEST ACCOUNT` in notes | `internal_notes` |
| Logical inconsistencies | Active subscriptions with an end date, end date before start date | `status`, `start_date`, `end_date` |

---

## Cleaning Pipeline

The final script builds `subscriptions_clean` through a chain of CTEs, where each step handles one type of problem:

1. **`clean_payment`**: Replaces `NULL`, `'NULL'` and `'N/A'` payment methods with `'Unknown'`. Lowercases and trims emails, converting blank strings to `NULL`.
2. **`stand_colm`**: Standardizes `status` (maps `CANCELED` to `CANCELLED`, `PAUSSED` to `PAUSED`), applies `INITCAP(TRIM())` to `plan`, maps country aliases to full names, and parses `start_date` using `COALESCE` with several `SAFE.PARSE_DATE` formats.
3. **`ranked` / `updated_info`**: Deduplicates by keeping the most recent record per `subscription_id` with `ROW_NUMBER() OVER (PARTITION BY ... ORDER BY updated_at DESC)`.
4. **`price_update`**: Converts negative prices to positive with `ABS()` and divides prices over 100 by 100 (cents to currency units).
5. **`QC`**: Adds a `qc_flag` column that describes any remaining rule violations.
6. **`test_remove`**: Excludes rows where `internal_notes` contains `TEST`, keeping rows where notes are `NULL`.

### Example: Standardizing Status

```sql
CASE
  WHEN UPPER(TRIM(status)) IN ('ACTIVE') THEN 'ACTIVE'
  WHEN UPPER(TRIM(status)) IN ('CANCELED','CANCELLED') THEN 'CANCELLED'
  WHEN UPPER(TRIM(status)) IN ('PAUSED','PAUSSED') THEN 'PAUSED'
  ELSE UPPER(TRIM(status))
END AS status
```

### Example: Deduplication

```sql
ROW_NUMBER() OVER (
  PARTITION BY subscription_id
  ORDER BY updated_at DESC
) AS row_num
```

### Example: Email Validation

```sql
IF(customer_email IS NULL,
   'Missing email, ', ''),

IF(customer_email IS NOT NULL
   AND NOT REGEXP_CONTAINS(customer_email, r'^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$'),
   'Invalid email format, ', '')
```

---

## Quality Control Flags

Rather than deleting questionable rows, the pipeline labels them in `qc_flag` so they can be reviewed. The counts below are from the final table.

| Flag | Rule | Rows flagged |
|---|---|---|
| No start date | `start_date` is `NULL` after parsing | 3 |
| Invalid start date | Start year is after 2027 | 2 |
| End date before start date | `end_date < start_date` | 5 |
| Active with end date | Status is active but an end date exists | 6 |
| Cancelled without end date | Status is cancelled but no end date exists | 5 |
| Free plan with different pricing | Free plan where price is not `0` | 0 |
| Basic plan with different pricing | Basic plan where price is not `9.99` | 5 |
| Premium plan with different pricing | Premium plan where price is not `19.99` | 1 |
| Missing email | `customer_email` is `NULL` | 5 |
| Invalid email format | Email does not match the regex pattern | 4 |

---

## Results

| Stage | Rows |
|---|---|
| Raw data | 162 |
| After removing duplicate `subscription_id`s | 150 |
| After removing test accounts (final) | 147 |

- **111** of the 147 final rows passed every QC check. **36** carry at least one flag.
- Status values reduced from 14 raw variants to 3 clean values: `ACTIVE`, `CANCELLED`, `PAUSED`.
- Plan values reduced from 15 variants to 3: `Free`, `Basic`, `Premium`.
- Country values reduced from 13 variants to 4: United Kingdom, Ireland, Germany, Italy.

---

## Repository Structure

```
.
├── README.md
├── sql/
│   └── Datacleaning.sql                  # Profiling queries + final cleaning pipeline
└── data/
    ├── subscriptions_raw.csv             # Raw input data
    └── subscriptions_clean_project.csv   # Cleaned output exported from BigQuery
```

## How to Run

1. Create a dataset in BigQuery (this project uses `Datacleaning`).
2. Upload `data/subscriptions_raw.csv` as a table named `subscriptions_raw`.
3. Replace the project ID in `sql/Datacleaning.sql` (`sql-portfolio-510408`) with your own.
4. Run the profiling queries to explore the data, then run the **Final cleaning pipeline** section to create `subscriptions_clean`.

---

## Assumptions and Limitations

- Prices above 100 are assumed to be stored in cents, and negative prices are assumed to be sign errors. These assumptions fit this dataset but should be confirmed with the data owner in a real setting.
- Ambiguous dates such as `03/04/2026` are parsed as `DD/MM/YYYY` after the ISO formats fail.
- `end_date` was already in a consistent `YYYY-MM-DD` format in the raw data, so only `start_date` required date parsing.
- The email check validates format only. It cannot detect typos in otherwise valid addresses (for example `gmial.com`) or confirm that a mailbox exists.
- Flagged rows are kept in the table so that downstream users can decide how to treat them.

## Possible Next Steps

- Build a dashboard (for example in Looker Studio) on the clean table for churn and revenue by plan and country.
- Add a summary query that reports the number of flagged rows by `qc_flag` type.
