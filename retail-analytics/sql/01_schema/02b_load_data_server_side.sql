-- =====================================================================
-- 02b_load_data_server_side.sql   (ALTERNATIVE to 02_load_data.sql)
-- Use when you CANNOT run psql (pgAdmin / DBeaver). Plain COPY, no backslash.
-- Requires the CSVs to sit on the DB server and your role to have file-read
-- rights (superusers do). If remote or you hit a permission error, use the
-- Python loader (load_data.py) instead.
-- Replace every {DIR} with the absolute CSV folder path (keep trailing slash).
-- Load order matters: parents before children.
-- =====================================================================

COPY raw.stores (store_id, store_name, city, state, region, store_type, open_date)
    FROM '{DIR}stores.csv' WITH (FORMAT csv, HEADER true);

COPY raw.products (product_id, product_name, category, subcategory, unit_cost, list_price, launch_date)
    FROM '{DIR}products.csv' WITH (FORMAT csv, HEADER true);

COPY raw.customers (customer_id, customer_name, home_state, signup_date, loyalty_tier, email_opt_in)
    FROM '{DIR}customers.csv' WITH (FORMAT csv, HEADER true);

COPY raw.orders (order_id, customer_id, store_id, channel, order_date, payment_method, order_discount_rate, is_returned, return_date)
    FROM '{DIR}orders.csv' WITH (FORMAT csv, HEADER true, NULL '');

COPY raw.order_items (order_item_id, order_id, product_id, quantity, unit_price, unit_cost, line_discount_rate)
    FROM '{DIR}order_items.csv' WITH (FORMAT csv, HEADER true);

ANALYZE;
