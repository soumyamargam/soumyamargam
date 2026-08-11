-- =====================================================================
-- 04_analysis/01_executive_kpis.sql
-- Executive summary KPIs + monthly revenue trend with growth.
-- =====================================================================

-- ---- Headline KPIs (single row) ----
SELECT
    COUNT(*)                                                          AS total_orders,
    COUNT(DISTINCT customer_id)                                       AS active_customers,
    ROUND(SUM(order_revenue), 2)                                      AS total_revenue,
    ROUND(SUM(order_profit), 2)                                       AS total_gross_profit,
    ROUND(100.0 * SUM(order_profit) /SUM(order_revenue), 1) AS gross_margin_pct,
    ROUND(SUM(order_revenue) / COUNT(*), 2)     						AS avg_order_value,
	round(100.0*sum(case when is_returned then order_revenue else 0 end)
          / SUM(order_revenue), 2)               AS returned_revenue_pct,
    ROUND(100.0 * sum(case when channel = 'Online' then 1 else 0 end) / COUNT(*), 1) AS online_order_pct
FROM staging.stg_orders;

-- ---- Monthly revenue trend with MoM growth and rolling 3-month average ----
WITH monthly AS (
    SELECT
        DATE_TRUNC('month', order_date)::date AS month,
        COUNT(*)               AS orders,
        SUM(order_revenue)     AS revenue,
        SUM(order_profit)      AS profit
    FROM staging.stg_orders
    GROUP BY DATE_TRUNC('month', order_date)
)
SELECT
    month,
    orders,
    ROUND(revenue, 0)                                                   AS revenue,
    ROUND(profit, 0)                                                    AS profit,
    ROUND(LAG(revenue) OVER (ORDER BY month), 0)                        AS prev_month_revenue,
    ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
          / LAG(revenue) OVER (ORDER BY month), 1)          AS mom_growth_pct,
    ROUND(AVG(revenue) OVER (ORDER BY month
                             ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 0) AS rolling_3mo_avg
FROM monthly
ORDER BY month;


