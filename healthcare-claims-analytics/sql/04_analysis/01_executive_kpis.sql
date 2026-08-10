-- =====================================================================
-- 01_executive_kpis.sql
-- Headline revenue-cycle KPIs. This is the query a director actually asks
-- for: one row, every number defined the same way every month.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q1. Executive KPI summary (single row)
-- ---------------------------------------------------------------------
SELECT
    COUNT(*)                                                      AS total_claims,
    SUM(billed_amount)                                            AS total_billed,
    SUM(allowed_amount)                                           AS total_allowed,
    SUM(final_paid_amount)                                        AS total_paid,

 -- First-pass denial rate: the single most watched RCM metric
ROUND(100.0 * SUM(CASE WHEN is_denied_first_pass THEN 1 ELSE 0 END)
    /
	SUM(CASE WHEN NOT is_pending THEN 1 ELSE 0 END),
    2
) AS first_pass_denial_rate_pct,


-- Clean claim rate: paid on the first submission, no rework
ROUND(
    100.0 * SUM(CASE WHEN claim_outcome = 'Paid First Pass' THEN 1 ELSE 0 END)
    /SUM(CASE WHEN NOT is_pending THEN 1 ELSE 0 END),2) AS clean_claim_rate_pct,


-- Of the claims denied first time, how many did we eventually win?
ROUND(
    100.0 * SUM(CASE WHEN is_overturned THEN 1 ELSE 0 END)
    /SUM(CASE WHEN is_denied_first_pass THEN 1 ELSE 0 END),2
) AS denial_overturn_rate_pct,

    -- Net collection rate: paid as a share of what we were entitled to
    ROUND(100.0 * SUM(final_paid_amount)
          /SUM(allowed_amount), 2)                    AS net_collection_rate_pct,

    ROUND(AVG(days_to_payment), 1)                                AS avg_days_to_payment,
    ROUND(AVG(days_to_first_response), 1)                         AS avg_days_to_first_response,

    sum(case when is_pending then 1 else 0 end)                            AS pending_claims,
    SUM(revenue_at_risk)                                          AS revenue_at_risk
FROM marts.fct_claim;


-- ---------------------------------------------------------------------
-- Q2. Monthly denial-rate trend with month-over-month change and a
--     3-month rolling average to smooth the noise.
--     (LAG + a bounded window frame)
-- ---------------------------------------------------------------------
WITH monthly AS (
    SELECT
        submission_month,
        sum(case when NOT is_pending then 1 else 0 end)                   AS adjudicated_claims,
        sum(case when is_denied_first_pass then 1 else 0 end)             AS denied_claims,
        -- ROUND(100.0 * sum(case when is_denied_first_pass then 1 else 0 end)
        --       / sum(case when not is_pending then 1 else 0 end), 2) AS denial_rate_pct,
			  
			  ROUND(
    100.0 *
    SUM(CASE WHEN is_denied_first_pass THEN 1 ELSE 0 END)
    / NULLIF(
        SUM(CASE WHEN NOT is_pending THEN 1 ELSE 0 END),
        0
    ),
    2
) AS denial_rate_pct,
        SUM(case when is_denied_first_pass then billed_amount else 0 end)   AS denied_charges
    FROM marts.fct_claim
    GROUP BY submission_month
)
SELECT
    submission_month,
    adjudicated_claims,
    denied_claims,
    denial_rate_pct,
    LAG(denial_rate_pct) OVER (ORDER BY submission_month)        AS prev_month_rate,
    ROUND(denial_rate_pct
          - LAG(denial_rate_pct) OVER (ORDER BY submission_month), 2) AS mom_change_pts,
    ROUND(AVG(denial_rate_pct) OVER (ORDER BY submission_month
                                     ROWS BETWEEN 2 PRECEDING
                                              AND CURRENT ROW), 2)    AS rolling_3mo_rate,
    denied_charges
FROM monthly
ORDER BY submission_month;
