-- =====================================================================
-- 01_create_schema.sql
-- Retail Analytics - raw (landing) layer
-- Omnichannel specialty retailer: customers place orders across stores
-- and online; each order has line items tying to products.
-- =====================================================================

DROP SCHEMA IF EXISTS raw CASCADE;
DROP SCHEMA IF EXISTS staging CASCADE;
DROP SCHEMA IF EXISTS marts CASCADE;

CREATE SCHEMA raw;
CREATE SCHEMA staging;
CREATE SCHEMA marts;

-- ---------------------------------------------------------------------
-- Dimensions
-- ---------------------------------------------------------------------
CREATE TABLE raw.stores (
    store_id     INTEGER      PRIMARY KEY,
    store_name   VARCHAR(60)  NOT NULL,
    city         VARCHAR(40)  NOT NULL,
    state        VARCHAR(2)   NOT NULL,
    region       VARCHAR(20)  NOT NULL,   -- West / South / Midwest / Northeast / Mountain / Online
    store_type   VARCHAR(20)  NOT NULL,   -- Flagship / Standard / Online
    open_date    DATE         NOT NULL
);

CREATE TABLE raw.products (
    product_id     INTEGER      PRIMARY KEY,
    product_name   VARCHAR(80)  NOT NULL,
    category       VARCHAR(30)  NOT NULL,   -- Apparel / Footwear / Accessories / Homeware / Tech
    subcategory    VARCHAR(30)  NOT NULL,
    unit_cost      NUMERIC(10,2) NOT NULL,  -- what the retailer pays
    list_price     NUMERIC(10,2) NOT NULL,  -- catalogue price before discount
    launch_date    DATE         NOT NULL
);

CREATE TABLE raw.customers (
    customer_id    INTEGER      PRIMARY KEY,
    customer_name  VARCHAR(80)  NOT NULL,
    home_state     VARCHAR(2)   NOT NULL,
    signup_date    DATE         NOT NULL,
    loyalty_tier   VARCHAR(10)  NOT NULL,   -- Gold / Silver / Bronze
    email_opt_in   BOOLEAN      NOT NULL
);

-- ---------------------------------------------------------------------
-- Fact: order header (one row per order)
-- ---------------------------------------------------------------------
CREATE TABLE raw.orders (
    order_id            BIGINT       PRIMARY KEY,
    customer_id         INTEGER      NOT NULL REFERENCES raw.customers(customer_id),
    store_id            INTEGER      NOT NULL REFERENCES raw.stores(store_id),
    channel             VARCHAR(15)  NOT NULL,   -- Online / In-Store
    order_date          DATE         NOT NULL,
    payment_method      VARCHAR(20)  NOT NULL,
    order_discount_rate NUMERIC(4,2) NOT NULL,   -- 0.00 .. 0.25
    is_returned         BOOLEAN      NOT NULL,
    return_date         DATE                     -- NULL unless the order was returned
);

-- ---------------------------------------------------------------------
-- Fact: order line detail (one row per product per order)
-- ---------------------------------------------------------------------
CREATE TABLE raw.order_items (
    order_item_id      BIGINT        PRIMARY KEY,
    order_id           BIGINT        NOT NULL REFERENCES raw.orders(order_id),
    product_id         INTEGER       NOT NULL REFERENCES raw.products(product_id),
    quantity           INTEGER       NOT NULL,
    unit_price         NUMERIC(10,2) NOT NULL,   -- actual selling price per unit (post-discount)
    unit_cost          NUMERIC(10,2) NOT NULL,   -- copied from product at time of sale
    line_discount_rate NUMERIC(4,2)  NOT NULL
);

CREATE INDEX idx_orders_customer  ON raw.orders(customer_id);
CREATE INDEX idx_orders_store     ON raw.orders(store_id);
CREATE INDEX idx_orders_date      ON raw.orders(order_date);
CREATE INDEX idx_items_order      ON raw.order_items(order_id);
CREATE INDEX idx_items_product    ON raw.order_items(product_id);
