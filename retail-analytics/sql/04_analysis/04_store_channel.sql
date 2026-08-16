-- =====================================================================
-- 04_analysis/04_store_channel.sql
-- Store scorecard + channel comparison + region ranking.
-- =====================================================================

-- ---- Store scorecard with within-type benchmarking ----
-- Each store benchmarked against the average of its own store_type,
-- so Flagships are compared with Flagships, not with Online.
WITH store_perf AS (
    SELECT
        s.store_id,
        s.store_name,
        s.region,
        s.store_type,
        COUNT(*)                          AS orders,
        SUM(o.order_revenue)              AS revenue,
        SUM(o.order_profit)               AS profit,
        ROUND(SUM(o.order_revenue) / COUNT(*), 2) AS avg_order_value,
        ROUND(100.0 * sum(case when o.is_returned then 1 else 0 end) / COUNT(*), 1) AS return_rate_pct
    FROM staging.stg_orders o
    JOIN raw.stores s ON s.store_id = o.store_id
    GROUP BY s.store_id, s.store_name, s.region, s.store_type
)
SELECT
    store_name,
    region,
    store_type,
    orders,
    ROUND(revenue, 0)                                                    AS revenue,
    avg_order_value,
    return_rate_pct,
    ROUND(AVG(avg_order_value) OVER (PARTITION BY store_type), 2)        AS type_avg_aov,
    RANK() OVER (ORDER BY revenue DESC)                                  AS revenue_rank
FROM store_perf
ORDER BY revenue DESC;

-- ---- Channel comparison ----
SELECT
    channel,
    COUNT(*)                                                            AS orders,
    COUNT(DISTINCT customer_id)                                         AS customers,
    ROUND(SUM(order_revenue), 0)                                        AS revenue,
    ROUND(SUM(order_revenue) / COUNT(*), 2)                             AS avg_order_value,
    ROUND(AVG(n_units), 1)                                              AS avg_units_per_order,
    ROUND(100.0 * SUM(order_profit) / SUM(order_revenue), 1) AS margin_pct,
    ROUND(100.0 * sum(case when is_returned then 1 else 0 end) / COUNT(*), 1)    AS return_rate_pct
FROM staging.stg_orders
GROUP BY channel
ORDER BY revenue DESC;

-- ---- Region ranking (physical stores only) ----
SELECT
    region,
    COUNT(DISTINCT store_id)                                            AS stores,
    COUNT(*)                                                            AS orders,
    ROUND(SUM(order_revenue), 0)                                        AS revenue,
    ROUND(100.0 * SUM(order_revenue) / SUM(SUM(order_revenue)) OVER (), 1) AS pct_of_revenue
FROM staging.stg_orders
WHERE channel = 'In-Store'
GROUP BY region
ORDER BY revenue DESC;
