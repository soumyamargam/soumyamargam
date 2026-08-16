-- =====================================================================
-- 04_analysis/05_market_basket.sql
-- Market-basket analysis: which product CATEGORIES are bought together,
-- with support, confidence and lift -- the standard association metrics.
--
--   support(A,B)    = P(order contains both A and B)
--   confidence(A>B) = P(B in order | A in order)
--   lift(A,B)       = confidence / P(B)   ( >1 => positive association )
-- Done at category grain to keep pairs interpretable and non-sparse.
-- =====================================================================

WITH order_cats AS (
    -- distinct categories per order
    SELECT DISTINCT order_id, category
    FROM staging.stg_order_items
),
total_orders AS (
    SELECT COUNT(DISTINCT order_id)::numeric AS n_orders FROM order_cats
),
cat_freq AS (
    -- how often each category appears (for the P(B) denominator in lift)
    SELECT category, COUNT(DISTINCT order_id)::numeric AS orders_with_cat
    FROM order_cats
    GROUP BY category
),
pairs AS (
    -- unordered category pairs that co-occur in an order
    SELECT
        a.category AS cat_a,
        b.category AS cat_b,
        COUNT(*)::numeric AS pair_orders
    FROM order_cats a
    JOIN order_cats b
      ON a.order_id = b.order_id
     AND a.category < b.category            -- avoid self-pairs and mirror duplicates
    GROUP BY a.category, b.category
)
SELECT
    p.cat_a,
    p.cat_b,
    p.pair_orders::int                                                   AS orders_together,
    ROUND(100.0 * p.pair_orders / t.n_orders, 2)                         AS support_pct,
    ROUND(100.0 * p.pair_orders / fa.orders_with_cat, 1)                 AS confidence_a_to_b_pct,
    ROUND(100.0 * p.pair_orders / fb.orders_with_cat, 1)                 AS confidence_b_to_a_pct,
    ROUND( (p.pair_orders / t.n_orders)
           / ((fa.orders_with_cat / t.n_orders) * (fb.orders_with_cat / t.n_orders)), 2) AS lift
FROM pairs p
CROSS JOIN total_orders t
JOIN cat_freq fa ON fa.category = p.cat_a
JOIN cat_freq fb ON fb.category = p.cat_b
ORDER BY lift DESC, orders_together DESC;
