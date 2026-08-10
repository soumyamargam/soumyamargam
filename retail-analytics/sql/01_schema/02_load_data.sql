-- =====================================================================
-- 02_load_data.sql   (psql version -- uses \copy)
-- Run from the project root with:  psql -d retail_db -f sql/01_schema/02_load_data.sql
-- If you cannot run psql (pgAdmin/DBeaver), use load_data.py or 02b instead.
-- Load order matters: parents before children (foreign keys).
-- =====================================================================

\copy raw.stores      FROM 'data/csv/stores.csv'      WITH (FORMAT csv, HEADER true);
\copy raw.products    FROM 'data/csv/products.csv'    WITH (FORMAT csv, HEADER true);
\copy raw.customers   FROM 'data/csv/customers.csv'   WITH (FORMAT csv, HEADER true);
\copy raw.orders      FROM 'data/csv/orders.csv'      WITH (FORMAT csv, HEADER true, NULL '');
\copy raw.order_items FROM 'data/csv/order_items.csv' WITH (FORMAT csv, HEADER true);

ANALYZE;
