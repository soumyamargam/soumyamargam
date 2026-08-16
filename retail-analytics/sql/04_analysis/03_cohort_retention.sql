-- =====================================================================
-- 04_analysis/03_cohort_retention.sql
-- Monthly acquisition cohorts and their retention over subsequent months.
-- Cohort = month of a customer's FIRST order.
-- Retention[n] = % of the cohort that ordered again n months later.
-- =====================================================================

WITH first_orders AS (
    SELECT
        customer_id,
        DATE_TRUNC('month', first_order_date)::date AS cohort_month
    FROM staging.stg_customers
    WHERE first_order_date IS NOT NULL
),
activity AS (
    -- every month in which each customer placed an order
    SELECT DISTINCT
        o.customer_id,
        f.cohort_month,
        DATE_TRUNC('month', o.order_date)::date AS activity_month,
        -- integer number of months between cohort and activity
        (EXTRACT(YEAR  FROM AGE(DATE_TRUNC('month', o.order_date), f.cohort_month)) * 12
       + EXTRACT(MONTH FROM AGE(DATE_TRUNC('month', o.order_date), f.cohort_month)))::int
            AS month_offset
    FROM staging.stg_orders o
    JOIN first_orders f ON f.customer_id = o.customer_id
),
cohort_size AS (
    SELECT cohort_month, COUNT(*) AS cohort_customers
    FROM first_orders
    GROUP BY cohort_month
),
retention AS (
    SELECT
        a.cohort_month,
        a.month_offset,
        COUNT(DISTINCT a.customer_id) AS active_customers
    FROM activity a
    GROUP BY a.cohort_month, a.month_offset
)
SELECT
    r.cohort_month,
    cs.cohort_customers,
    r.month_offset,
    r.active_customers,
    ROUND(100.0 * r.active_customers / cs.cohort_customers, 1) AS retention_pct
FROM retention r
JOIN cohort_size cs ON cs.cohort_month = r.cohort_month
WHERE r.cohort_month <= DATE '2024-06-01'   -- cohorts with room to mature
  AND r.month_offset <= 6
ORDER BY r.cohort_month, r.month_offset;
