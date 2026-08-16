-- =====================================================================
-- 05_tests/data_quality_checks.sql
-- 20 assertion checks. Each returns PASS or FAIL. All should PASS on a
-- clean build. Run after building staging + marts.
-- =====================================================================

SELECT check_name, status, detail FROM (

-- 1. Every order has at least one line item
SELECT 1 AS ord, 'orders_have_line_items' AS check_name,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status,
       COUNT(*)::text || ' orphan orders' AS detail
FROM raw.orders o
WHERE NOT EXISTS (SELECT 1 FROM raw.order_items i WHERE i.order_id = o.order_id)

UNION ALL
-- 2. No order_items reference a missing order
SELECT 2, 'items_have_valid_order',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text || ' orphan items'
FROM raw.order_items i
LEFT JOIN raw.orders o ON o.order_id = i.order_id
WHERE o.order_id IS NULL

UNION ALL
-- 3. No order_items reference a missing product
SELECT 3, 'items_have_valid_product',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text || ' bad product refs'
FROM raw.order_items i
LEFT JOIN raw.products p ON p.product_id = i.product_id
WHERE p.product_id IS NULL

UNION ALL
-- 4. No orders reference a missing customer
SELECT 4, 'orders_have_valid_customer',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text || ' bad customer refs'
FROM raw.orders o
LEFT JOIN raw.customers c ON c.customer_id = o.customer_id
WHERE c.customer_id IS NULL

UNION ALL
-- 5. No orders reference a missing store
SELECT 5, 'orders_have_valid_store',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text || ' bad store refs'
FROM raw.orders o
LEFT JOIN raw.stores s ON s.store_id = o.store_id
WHERE s.store_id IS NULL

UNION ALL
-- 6. Quantities are strictly positive
SELECT 6, 'quantity_positive',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text || ' non-positive qty'
FROM raw.order_items WHERE quantity <= 0

UNION ALL
-- 7. Unit prices are non-negative
SELECT 7, 'unit_price_non_negative',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text || ' negative prices'
FROM raw.order_items WHERE unit_price < 0

UNION ALL
-- 8. Unit cost never exceeds list price on the product master
SELECT 8, 'cost_not_above_list',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text || ' products cost>list'
FROM raw.products WHERE unit_cost > list_price

UNION ALL
-- 9. Returned orders have a return_date
SELECT 9, 'returned_orders_have_date',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text || ' returned w/o date'
FROM raw.orders WHERE is_returned AND return_date IS NULL

UNION ALL
-- 10. Non-returned orders have no return_date
SELECT 10, 'non_returned_no_date',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text || ' not-returned w/ date'
FROM raw.orders WHERE NOT is_returned AND return_date IS NOT NULL

UNION ALL
-- 11. Return date is on or after the order date
SELECT 11, 'return_after_order',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text || ' returns before order'
FROM raw.orders WHERE return_date IS NOT NULL AND return_date < order_date

UNION ALL
-- 12. Order dates fall within the expected reporting window
SELECT 12, 'order_date_in_window',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text || ' out-of-window'
FROM raw.orders
WHERE order_date < DATE '2023-01-01' OR order_date > DATE '2024-12-31'

UNION ALL
-- 13. order_id is unique (primary key integrity, belt-and-braces)
SELECT 13, 'order_id_unique',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text || ' dup order_ids'
FROM (SELECT order_id FROM raw.orders GROUP BY order_id HAVING COUNT(*) > 1) d

UNION ALL
-- 14. Discount rates are within 0..0.25
SELECT 14, 'discount_rate_in_range',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text || ' bad discount rates'
FROM raw.orders WHERE order_discount_rate < 0 OR order_discount_rate > 0.25

UNION ALL
-- 15. Loyalty tiers are from the known set
SELECT 15, 'loyalty_tier_valid',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text || ' bad tiers'
FROM raw.customers WHERE loyalty_tier NOT IN ('Gold','Silver','Bronze')

UNION ALL
-- 16. Channels are from the known set
SELECT 16, 'channel_valid',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text || ' bad channels'
FROM raw.orders WHERE channel NOT IN ('Online','In-Store')

UNION ALL
-- 17. staging order revenue reconciles to raw line items (penny-exact)
SELECT 17, 'staging_revenue_reconciles',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text || ' mismatched orders'
FROM (
    SELECT o.order_id
    FROM staging.stg_orders o
    JOIN (SELECT order_id, ROUND(SUM(quantity*unit_price),2) AS rev
          FROM raw.order_items GROUP BY order_id) r ON r.order_id = o.order_id
    WHERE ABS(o.order_revenue - r.rev) > 0.01
) x

UNION ALL
-- 18. RFM mart has exactly one row per purchasing customer
SELECT 18, 'rfm_one_row_per_customer',
       CASE WHEN a.n = b.n THEN 'PASS' ELSE 'FAIL' END,
       'rfm='||a.n||' vs buyers='||b.n
FROM (SELECT COUNT(*) n FROM marts.fct_customer_rfm) a,
     (SELECT COUNT(DISTINCT customer_id) n FROM raw.orders) b

UNION ALL
-- 19. Every RFM customer has a valid segment label
SELECT 19, 'rfm_segment_populated',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text || ' null segments'
FROM marts.fct_customer_rfm WHERE rfm_segment IS NULL

UNION ALL
-- 20. RFM lifetime_revenue matches the sum of that customer's orders
SELECT 20, 'rfm_ltv_reconciles',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)::text || ' mismatched LTV'
FROM (
    SELECT r.customer_id
    FROM marts.fct_customer_rfm r
    JOIN (SELECT customer_id, ROUND(SUM(order_revenue),2) AS rev
          FROM staging.stg_orders GROUP BY customer_id) o ON o.customer_id = r.customer_id
    WHERE ABS(r.lifetime_revenue - o.rev) > 0.01
) y

) checks
ORDER BY ord;
