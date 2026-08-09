-- =====================================================================
-- 03_payer_scorecard.sql
-- Payer performance scorecard.
--
-- Contract negotiations need evidence. This ranks every payer on denial
-- behaviour, speed of payment and collection yield, and shows each one
-- against the book-of-business average so an outlier is obvious.
-- =====================================================================

WITH payer_metrics AS (
    SELECT
        p.payer_id,
        p.payer_name,
        p.payer_type,
        COUNT(*)                                                  AS total_claims,
        SUM(f.billed_amount)                                      AS billed,
        SUM(f.allowed_amount)                                     AS allowed,
        SUM(f.final_paid_amount)                                  AS paid,
        ROUND(100.0 * sum(case when f.is_denied_first_pass then 1 else 0 end)
              / sum(case when NOT f.is_pending then 1 else 0 end), 2)  AS denial_rate_pct,
        ROUND(100.0 * sum(case when f.is_overturned then 1 else 0 end)
              / sum(case when f.is_denied_first_pass then 1 else 0 end), 2) AS overturn_rate_pct,
        ROUND(100.0 * SUM(f.final_paid_amount)
              / SUM(f.allowed_amount), 2)              AS net_collection_pct,
        ROUND(AVG(f.days_to_payment), 1)                          AS avg_days_to_pay,
        SUM(f.revenue_at_risk)                                    AS revenue_at_risk
    FROM marts.fct_claim f
    JOIN raw.payers p ON p.payer_id = f.payer_id
    GROUP BY p.payer_id, p.payer_name, p.payer_type
)
SELECT
    payer_name,
    payer_type,
    total_claims,
    denial_rate_pct,
    -- rank payers worst-first on denials
    RANK() OVER (ORDER BY denial_rate_pct DESC)              AS denial_rank,
    -- every payer against the portfolio average, computed inline
    ROUND(AVG(denial_rate_pct) OVER (), 2)                   AS book_avg_denial_pct,
    ROUND(denial_rate_pct - AVG(denial_rate_pct) OVER (), 2) AS variance_vs_book_pts,
    CASE
        WHEN denial_rate_pct > AVG(denial_rate_pct) OVER () * 1.20 THEN 'Escalate'
        WHEN denial_rate_pct > AVG(denial_rate_pct) OVER ()        THEN 'Monitor'
        ELSE                                                            'Healthy'
    END                                                      AS action_flag,
    overturn_rate_pct,
    net_collection_pct,
    avg_days_to_pay,
    RANK() OVER (ORDER BY avg_days_to_pay DESC)              AS slowest_payer_rank,
    revenue_at_risk
FROM payer_metrics
ORDER BY denial_rate_pct DESC;
