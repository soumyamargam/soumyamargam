-- =====================================================================
-- 05_ar_aging_and_opportunity.sql
-- Two questions finance always asks:
--   (a) How old is our unpaid A/R, and how much is in the danger zone?
--   (b) If we fix the preventable denials, what is that actually worth?
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q1. A/R ageing on claims with no payer response yet.
--     Anything past 90 days is at serious risk of timely-filing loss.
-- ---------------------------------------------------------------------
SELECT
    ar_bucket,
    COUNT(*)                                                 AS open_claims,
    SUM(billed_amount)                                       AS billed_in_bucket,
    SUM(allowed_amount)                                      AS expected_value,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)       AS pct_of_open_claims,
    -- cumulative share as A/R gets older
    ROUND(100.0 * SUM(SUM(allowed_amount)) OVER (ORDER BY MIN(ar_days)
                                                 ROWS BETWEEN UNBOUNDED PRECEDING
                                                          AND CURRENT ROW)
          / SUM(SUM(allowed_amount)) OVER (), 2)             AS cumulative_value_pct,
    ROUND(AVG(ar_days), 1)                                   AS avg_age_days
FROM marts.fct_claim
WHERE is_pending
GROUP BY ar_bucket
ORDER BY MIN(ar_days);


-- ---------------------------------------------------------------------
-- Q2. Recovery opportunity: what are preventable denials costing us?
--     Split by the team that owns the root cause, so the output is a
--     work list rather than a statistic.
-- ---------------------------------------------------------------------
WITH denial_detail AS (
    SELECT
        d.typical_owner,
        d.denial_category,
        d.is_preventable,
        f.allowed_amount,
        f.is_overturned,
        f.is_denied_final
    FROM marts.fct_claim f
    JOIN raw.denial_codes d ON d.carc_code = f.first_carc_code
    WHERE f.is_denied_first_pass
)

SELECT
    typical_owner AS owning_team,
    COUNT(*) AS denied_claims,
    SUM(
        CASE
            WHEN is_preventable THEN 1
            ELSE 0
        END
    ) AS preventable_claims,
    ROUND(
        100.0 * SUM(
            CASE
                WHEN is_preventable THEN 1
                ELSE 0
            END
        ) / NULLIF(COUNT(*), 0),
        1
    ) AS pct_preventable,
    -- Money never recovered because the denial stuck
    SUM(
        CASE
            WHEN is_denied_final THEN allowed_amount
            ELSE 0
        END
    ) AS unrecovered_value,
    -- Money recovered, but only after rework the team could have avoided
    SUM(
        CASE
            WHEN is_overturned AND is_preventable
            THEN allowed_amount
            ELSE 0
        END
    ) AS avoidable_rework_value,
    ROUND(
        100.0 * SUM(
            CASE
                WHEN is_overturned THEN 1
                ELSE 0
            END
        ) / NULLIF(COUNT(*), 0),
        1
    ) AS overturn_rate_pct,
    RANK() OVER (
        ORDER BY
            SUM(
                CASE
                    WHEN is_denied_final THEN allowed_amount
                    ELSE 0
                END
            ) DESC NULLS LAST
    ) AS priority_rank

FROM denial_detail

GROUP BY typical_owner

ORDER BY unrecovered_value DESC NULLS LAST;