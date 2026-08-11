-- =====================================================================
-- 04_analysis/02_product_performance.sql
-- Category & product performance: ranking, margin, and 80/20 Pareto.
-- =====================================================================

-- ---- Category scorecard: revenue, margin, share, rank ----
SELECT
    category,
    ROUND(SUM(line_revenue), 0)                                          AS revenue,
    ROUND(SUM(line_profit), 0)                                           AS gross_profit,
    ROUND(100.0 * SUM(line_profit) / SUM(line_revenue), 1)    AS margin_pct,
    SUM(quantity)                                                        AS units_sold,
    ROUND(100.0 * SUM(line_revenue)
          / SUM(SUM(line_revenue)) OVER (), 1)                           AS pct_of_total_revenue,
    RANK() OVER (ORDER BY SUM(line_revenue) DESC)                        AS revenue_rank,
    RANK() OVER (ORDER BY SUM(line_profit) DESC)                         AS profit_rank
FROM staging.stg_order_items
GROUP BY category
ORDER BY revenue DESC;

-- ---- Product Pareto: do 20% of products drive 80% of revenue? ----
WITH product_rev AS (
    SELECT
        i.product_id,
        p.product_name,
        p.category,
        SUM(i.line_revenue) AS revenue
    FROM staging.stg_order_items i
    JOIN raw.products p ON p.product_id = i.product_id
    GROUP BY i.product_id, p.product_name, p.category
),
ranked AS (
    SELECT
        product_id, product_name, category, revenue,
        ROW_NUMBER() OVER (ORDER BY revenue DESC)                         AS revenue_rank,
        SUM(revenue) OVER (ORDER BY revenue DESC
                           ROWS BETWEEN UNBOUNDED PRECEDING
                                    AND CURRENT ROW)                      AS cumulative_revenue,
        SUM(revenue) OVER ()                                             AS total_revenue,
        COUNT(*)     OVER ()                                             AS total_products
    FROM product_rev
)


SELECT
    revenue_rank,
    product_name,
    category,
    ROUND(revenue, 0)                                                    AS revenue,
	total_revenue,
    ROUND(100.0 * cumulative_revenue / total_revenue, 1)                 AS cumulative_pct,
    ROUND(100.0 * revenue_rank / total_products, 1)                      AS product_pct
FROM ranked
WHERE revenue_rank <= 15
   OR ROUND(100.0 * cumulative_revenue / total_revenue, 1) <= 80.5
ORDER BY revenue_rank

