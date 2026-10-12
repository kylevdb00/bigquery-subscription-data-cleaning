SELECT * FROM `sql-portfolio-510408.Datacleaning.subscriptions_raw` LIMIT 1000

-- Completeness of dataset
-- Counting NULL values of relevant columns (adjusted to exclude non NULL columns)

SELECT 
  COUNT(*) AS total_rows,
  COUNTIF(customer_email IS NULL) AS missing_email,
  COUNTIF(start_date IS NULL) AS missing_start_date,
  COUNTIF(end_date IS NULL) AS missing_end_date,
  COUNTIF(payment_method IS NULL) as missing_payment_method

FROM `sql-portfolio-510408.Datacleaning.subscriptions_raw`

--Detecting values that are unkown or duplicates

SELECT
  payment_method,
  COUNT(*) AS total_rows
FROM `sql-portfolio-510408.Datacleaning.subscriptions_raw`
GROUP BY payment_method
ORDER BY total_rows DESC

SELECT
  plan,
  COUNT(*) AS total_rows
FROM `sql-portfolio-510408.Datacleaning.subscriptions_raw`
GROUP BY 1
ORDER BY total_rows DESC

SELECT
  status,
  COUNT(*) AS total_rows
FROM `sql-portfolio-510408.Datacleaning.subscriptions_raw`
GROUP BY 1
ORDER BY total_rows DESC

SELECT
  country,
  COUNT(*) AS total_rows
FROM `sql-portfolio-510408.Datacleaning.subscriptions_raw`
GROUP BY 1
ORDER BY total_rows DESC

SELECT
  customer_email,
  COUNT(*) AS total_rows
FROM `sql-portfolio-510408.Datacleaning.subscriptions_raw`
GROUP BY 1
HAVING total_rows >1
ORDER BY total_rows DESC

SELECT
  subscription_id,
  COUNT(*) AS total_rows
FROM `sql-portfolio-510408.Datacleaning.subscriptions_raw`
GROUP BY 1
HAVING total_rows >1
ORDER BY total_rows DESC

SELECT
  customer_id,
  COUNT(*) AS total_rows
FROM `sql-portfolio-510408.Datacleaning.subscriptions_raw`
GROUP BY 1
HAVING total_rows >1
ORDER BY total_rows DESC


-- Setting irregular naming and NULLS to Unknown

SELECT 
  * EXCEPT (payment_method, customer_email),
  CASE
    WHEN payment_method IS NULL OR payment_method IN ('NULL','N/A') THEN 'Unknown'
    ELSE payment_method
  END AS payment_method_clean,
  NULLIF(LOWER(TRIM(customer_email)), '') AS customer_email
FROM `sql-portfolio-510408.Datacleaning.subscriptions_raw`

--Standardizing naming in columns

SELECT
  CASE
    WHEN UPPER(TRIM(status)) IN ('ACTIVE') THEN 'ACTIVE'
    WHEN UPPER(TRIM(status)) IN ('CANCELED','CANCELLED') THEN 'CANCELLED'
    WHEN UPPER(TRIM(status)) IN ('PAUSED','PAUSSED') THEN 'PAUSED'
    ELSE UPPER(TRIM(status))
  END AS status_clean,

  INITCAP(TRIM(plan)) AS plan,
  CASE
    WHEN UPPER(TRIM(country)) IN ('UNITED KINGDOM','UK','U.K.') THEN 'United Kingdom'
    WHEN UPPER(TRIM(country)) IN ('IRELAND','IE','I.E.') THEN 'Ireland'
    WHEN UPPER(TRIM(country)) IN ('GERMANY','DE','D.E.') THEN 'Germany'
    WHEN UPPER(TRIM(country)) IN ('ITALY','IT','I.T.') THEN 'Italy'
    ELSE INITCAP(TRIM(country))
  END AS country_clean,

  COALESCE(
    SAFE.PARSE_DATE('%Y-%m-%d',start_date),
    SAFE.PARSE_DATE('%Y/%m/%d',start_date),
    SAFE.PARSE_DATE('%d/%m/%Y', start_date),
    SAFE.PARSE_DATE('%d-%m-%Y', start_date)
  ) as start_date_clean

FROM `sql-portfolio-510408.Datacleaning.subscriptions_raw`


-- Updating duplicate subscriptions

WITH ranked as (
SELECT 
  *,
  ROW_NUMBER() OVER (PARTITION BY subscription_id ORDER BY updated_at DESC) AS row_num
FROM `sql-portfolio-510408.Datacleaning.subscriptions_raw`
)
SELECT * EXCEPT(row_num) 
FROM ranked
WHERE row_num = 1

--Monthly price validation

SELECT 
  monthly_price,
  count(*) as total_rows
FROM `sql-portfolio-510408.Datacleaning.subscriptions_raw`
GROUP BY 1
ORDER BY total_rows DESC

SELECT 
  CASE
    WHEN monthly_price < 0 then ABS(monthly_price)
    WHEN monthly_price > 100 THEN monthly_price/100
    ELSE monthly_price
  END AS monthly_price_clean
FROM `sql-portfolio-510408.Datacleaning.subscriptions_raw`

--Quality control and validation of columns

WITH QC as (
SELECT
  CONCAT(
    IF(start_date IS NULL,
       'No start date, ', ''),
      
    IF(LOWER(status) LIKE '%active%' AND end_date IS NOT NULL,
       'Active with end date, ', ''),

    IF(LOWER(status) LIKE '%cancelled%' AND end_date IS NULL,
       'Cancelled without end date, ', ''),

    IF(LOWER(plan) LIKE '%free%' AND monthly_price != 0,
       'Free plan with different pricing, ', ''),

    IF(LOWER(plan) LIKE '%basic%' AND monthly_price != 9.99,
       'Basic plan with different pricing, ', ''),

    IF(LOWER(plan) LIKE '%premium%' AND monthly_price != 19.99,
       'Premium plan with different pricing, ', '')
  ) AS qc_flag

FROM `sql-portfolio-510408.Datacleaning.subscriptions_raw`
)

SELECT * FROM QC
WHERE qc_flag is not null and qc_flag != ''

--Excluding test accounts

SELECT *
FROM `sql-portfolio-510408.Datacleaning.subscriptions_raw`
WHERE internal_notes NOT LIKE '%TEST%'

--Final cleaning pipeline
CREATE OR REPLACE TABLE `sql-portfolio-510408.Datacleaning.subscriptions_clean` AS

WITH clean_payment AS (
SELECT 
  * EXCEPT (payment_method, customer_email),
  CASE
    WHEN payment_method IS NULL OR payment_method IN ('NULL','N/A') THEN 'Unknown'
    ELSE payment_method
  END AS payment_method,
  NULLIF(LOWER(TRIM(customer_email)), '') AS customer_email
FROM `sql-portfolio-510408.Datacleaning.subscriptions_raw`
),
 stand_colm AS (
SELECT * EXCEPT(status,plan,start_date,country),
  CASE
    WHEN UPPER(TRIM(status)) IN ('ACTIVE') THEN 'ACTIVE'
    WHEN UPPER(TRIM(status)) IN ('CANCELED','CANCELLED') THEN 'CANCELLED'
    WHEN UPPER(TRIM(status)) IN ('PAUSED','PAUSSED') THEN 'PAUSED'
    ELSE UPPER(TRIM(status))
  END AS status,

  INITCAP(TRIM(plan)) AS plan,
  CASE
    WHEN UPPER(TRIM(country)) IN ('UNITED KINGDOM','UK','U.K.') THEN 'United Kingdom'
    WHEN UPPER(TRIM(country)) IN ('IRELAND','IE','I.E.') THEN 'Ireland'
    WHEN UPPER(TRIM(country)) IN ('GERMANY','DE','D.E.') THEN 'Germany'
    WHEN UPPER(TRIM(country)) IN ('ITALY','IT','I.T.') THEN 'Italy'
    ELSE INITCAP(TRIM(country))
  END AS country,

  COALESCE(
    SAFE.PARSE_DATE('%Y-%m-%d',start_date),
    SAFE.PARSE_DATE('%Y/%m/%d',start_date),
    SAFE.PARSE_DATE('%d/%m/%Y', start_date),
    SAFE.PARSE_DATE('%d-%m-%Y', start_date)
  ) as start_date

FROM clean_payment
),

ranked as (
SELECT 
  *,
  ROW_NUMBER() OVER (PARTITION BY subscription_id ORDER BY updated_at DESC) AS row_num
FROM stand_colm
),
 updated_info AS (
SELECT * EXCEPT(row_num) 
FROM ranked
WHERE row_num = 1
),

price_update as (
SELECT * EXCEPT(monthly_price),
  CASE
    WHEN monthly_price < 0 THEN ABS(monthly_price)
    WHEN monthly_price > 100 THEN monthly_price / 100
    ELSE monthly_price
  END AS monthly_price
FROM updated_info
),

QC as (
SELECT *,
  CONCAT(
    IF(start_date IS NULL,
       'No start date, ', ''),
    IF(EXTRACT(YEAR FROM start_date) > 2027,
   'Invalid start date, ',''),

    IF(end_date < start_date, 'End date before start date, ', ''),

    IF(LOWER(status) LIKE '%active%' AND end_date IS NOT NULL,
       'Active with end date, ', ''),

    IF(LOWER(status) LIKE '%cancelled%' AND end_date IS NULL,
       'Cancelled without end date, ', ''),

    IF(LOWER(plan) LIKE '%free%' AND monthly_price != 0,
       'Free plan with different pricing, ', ''),

    IF(LOWER(plan) LIKE '%basic%' AND monthly_price != 9.99,
       'Basic plan with different pricing, ', ''),

    IF(LOWER(plan) LIKE '%premium%' AND monthly_price != 19.99,
       'Premium plan with different pricing, ', '')
  ) AS qc_flag

FROM price_update
),

test_remove as (SELECT *
FROM QC
WHERE internal_notes NOT LIKE '%TEST%' OR internal_notes IS NULL
)


SELECT subscription_id,
  customer_id,
  customer_email,
  country,
  plan,
  monthly_price,
  status,
  start_date,
  end_date,
  payment_method,
  updated_at,
  internal_notes,
  qc_flag
FROM test_remove

