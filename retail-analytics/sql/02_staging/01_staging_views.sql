-- =====================================================================
-- 02_staging/01_staging_views.sql
-- Staging layer: light cleaning + derived fields on top of raw.
-- One view per raw table where useful, plus reporting config.
-- =====================================================================

-- Central reporting "as of" date so every metric is reproducible.
CREATE OR REPLACE VIEW staging.stg_reporting_config AS
SELECT DATE '2024-12-31' AS as_of_date;

-- Order lines enriched with product + true economics.
-- line_revenue  = what the customer paid for the line
-- line_cost     = what those units cost the retailer
-- line_profit   = gross profit on the line
CREATE OR REPLACE VIEW staging.stg_order_items AS
SELECT
    i.order_item_id,
    i.order_id,
    i.product_id,
    p.category,
    p.subcategory,
    i.quantity,
    i.unit_price,
    i.unit_cost,
    i.line_discount_rate,
    ROUND(i.quantity * i.unit_price, 2)                    AS line_revenue,
    ROUND(i.quantity * i.unit_cost, 2)                     AS line_cost,
    ROUND(i.quantity * (i.unit_price - i.unit_cost), 2)    AS line_profit,
    ROUND(i.quantity * p.list_price, 2)                    AS line_gross_before_discount
FROM raw.order_items i
JOIN raw.products p ON p.product_id = i.product_id;

-- Orders enriched with customer + store context, plus one row of
-- pre-aggregated line economics so downstream code never re-aggregates.
CREATE OR REPLACE VIEW staging.stg_orders AS
SELECT
    o.order_id,
    o.customer_id,
    o.store_id,
    s.store_name,
    s.region,
    s.store_type,
    o.channel,
    o.order_date,
    o.payment_method,
    o.order_discount_rate,
    o.is_returned,
    o.return_date,
    c.loyalty_tier,
    c.home_state,
    c.signup_date,
    li.n_items,
    li.n_units,
    li.order_revenue,
    li.order_cost,
    li.order_profit
FROM raw.orders o
JOIN raw.customers c ON c.customer_id = o.customer_id
JOIN raw.stores    s ON s.store_id    = o.store_id
JOIN (
    SELECT order_id,
           COUNT(*)              AS n_items,
           SUM(quantity)         AS n_units,
           SUM(line_revenue)     AS order_revenue,
           SUM(line_cost)        AS order_cost,
           SUM(line_profit)      AS order_profit
    FROM staging.stg_order_items
    GROUP BY order_id
) li ON li.order_id = o.order_id;

-- Customers with first/last order dates and lifetime aggregates.
-- Cohort is defined by FIRST ORDER month (standard retail practice),
-- not signup, so pre-window signups still cohort cleanly.
CREATE OR REPLACE VIEW staging.stg_customers AS
SELECT
    c.customer_id,
    c.customer_name,
    c.home_state,
    c.signup_date,
    c.loyalty_tier,
    c.email_opt_in,
    o.first_order_date,
    o.last_order_date,
    DATE_TRUNC('month', o.first_order_date)::date AS cohort_month,
    o.orders_count,
    o.lifetime_revenue,
    o.lifetime_profit
FROM raw.customers c
LEFT JOIN (
    SELECT customer_id,
           MIN(order_date)        AS first_order_date,
           MAX(order_date)        AS last_order_date,
           COUNT(*)               AS orders_count,
           SUM(order_revenue)     AS lifetime_revenue,
           SUM(order_profit)      AS lifetime_profit
    FROM staging.stg_orders
    GROUP BY customer_id
) o ON o.customer_id = c.customer_id;
