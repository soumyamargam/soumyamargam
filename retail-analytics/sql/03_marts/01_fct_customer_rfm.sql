-- =====================================================================
-- 03_marts/01_fct_customer_rfm.sql
-- CORE MART: one row per customer who has ordered, with RFM scoring.
--
-- RFM = Recency, Frequency, Monetary -- the standard retail framework for
-- customer segmentation:
--   Recency   = days since last order (smaller = better)
--   Frequency = number of orders
--   Monetary  = lifetime revenue
--
-- Each dimension is scored 1-5 using NTILE (quintiles), then combined into
-- a named segment. Scored only over customers who have actually ordered.
-- =====================================================================

DROP TABLE IF EXISTS marts.fct_customer_rfm;

CREATE TABLE marts.fct_customer_rfm AS
WITH base AS (
    SELECT
        c.customer_id,
        c.customer_name,
        c.loyalty_tier,
        c.home_state,
        c.cohort_month,
        c.first_order_date,
        c.last_order_date,
        c.orders_count,
        c.lifetime_revenue,
        c.lifetime_profit,
        (SELECT as_of_date FROM staging.stg_reporting_config) AS as_of_date,
        ((SELECT as_of_date FROM staging.stg_reporting_config) - c.last_order_date) AS recency_days
    FROM staging.stg_customers c
    WHERE c.orders_count IS NOT NULL          -- exclude never-purchased
),
scored AS (
    SELECT
        base.*,
        -- Recency: fewer days = better, so invert so 5 = most recent
        6 - NTILE(5) OVER (ORDER BY recency_days ASC)              AS r_score_raw,
        NTILE(5) OVER (ORDER BY orders_count ASC)                 AS f_score,
        NTILE(5) OVER (ORDER BY lifetime_revenue ASC)             AS m_score
    FROM base
),
final AS (
    SELECT
        customer_id, customer_name, loyalty_tier, home_state, cohort_month,
        first_order_date, last_order_date, as_of_date, recency_days,
        orders_count, lifetime_revenue, lifetime_profit,
        r_score_raw AS r_score,
        f_score,
        m_score,
        (r_score_raw + f_score + m_score) AS rfm_total,
        CASE
            WHEN r_score_raw >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
            WHEN r_score_raw >= 4 AND f_score >= 3                  THEN 'Loyal'
            WHEN r_score_raw >= 4 AND f_score <= 2                  THEN 'New / Promising'
            WHEN r_score_raw = 3  AND f_score >= 3                  THEN 'Needs Attention'
            WHEN r_score_raw <= 2 AND f_score >= 4                  THEN 'At Risk'
            WHEN r_score_raw <= 2 AND m_score >= 4                  THEN 'Cant Lose Them'
            WHEN r_score_raw <= 2 AND f_score <= 2                  THEN 'Lost'
            ELSE 'Hibernating'
        END AS rfm_segment
    FROM scored
)
SELECT * FROM final;

ALTER TABLE marts.fct_customer_rfm ADD PRIMARY KEY (customer_id);
CREATE INDEX idx_rfm_segment ON marts.fct_customer_rfm(rfm_segment);
CREATE INDEX idx_rfm_cohort  ON marts.fct_customer_rfm(cohort_month);
