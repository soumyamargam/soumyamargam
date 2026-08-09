-- =====================================================================
-- 02_denial_pareto.sql
-- Which denial reasons actually matter?
--
-- A ranked list alone is not an answer - leadership needs to know how few
-- reasons you must fix to move the number. A running total over the sorted
-- list turns the list into a Pareto curve and names the vital few.
-- =====================================================================

WITH denial_base AS (
    SELECT
        f.first_carc_code                       AS carc_code,
        d.denial_reason,
        d.denial_category,
        d.is_preventable,
        d.typical_owner,
        f.billed_amount,
        f.allowed_amount,
        f.is_overturned
    FROM marts.fct_claim f
    JOIN raw.denial_codes d ON d.carc_code = f.first_carc_code
    WHERE f.is_denied_first_pass
),

agg AS (
    SELECT
        carc_code,
        denial_reason,
        denial_category,
        is_preventable,
        typical_owner,
        COUNT(*)                                          AS denied_claims,
        SUM(billed_amount)                                AS denied_charges,
        SUM(allowed_amount)                               AS allowed_at_stake,
        ROUND(100.0 * sum(case when is_overturned then 1 else 0 end)
              / COUNT(*), 1)                              AS overturn_rate_pct
    FROM denial_base
    GROUP BY carc_code, denial_reason, denial_category, is_preventable, typical_owner
)
SELECT
    RANK() OVER (ORDER BY denied_claims DESC)             AS rnk,
    carc_code,
    denial_reason,
    denial_category,
    typical_owner,
    is_preventable,
    denied_claims,
    ROUND(100.0 * denied_claims / SUM(denied_claims) OVER (), 2)
                                                          AS indiv_pct_of_denials,

	SUM(denied_claims) OVER (ORDER BY denied_claims DESC
                                           )
                         AS cumulative_value,
	ROUND(100.0 * (denied_claims)
          / SUM(denied_claims) OVER (), 2)                AS cumulative_pct,
    -- the Pareto column: cumulative share as you walk down the ranked list
    ROUND(100.0 * SUM(denied_claims) OVER (ORDER BY denied_claims DESC
                                           ROWS BETWEEN UNBOUNDED PRECEDING
                                                    AND CURRENT ROW)
          / SUM(denied_claims) OVER (), 2)                AS cumulative_pct,
    denied_charges,
    overturn_rate_pct
FROM agg
ORDER BY denied_claims DESC;