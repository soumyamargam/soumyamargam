-- =====================================================================
-- 04_provider_outliers.sql
-- Which providers are driving denials - and is it really their fault?
--
-- A raw denial-rate league table punishes specialties that are simply
-- harder to get paid for. The fair comparison is each provider against
-- their OWN specialty's average, which a window function gives us without
-- a second pass over the data.
--
-- Output feeds a targeted education list rather than a blanket memo.
-- =====================================================================
WITH provider_metrics AS (
    SELECT
        pr.provider_id,
        pr.provider_name,
        pr.specialty,
        pr.provider_type,
        pr.network_status,
        COUNT(*)                                                    AS total_claims,
        sum(case when f.is_denied_first_pass then 1 else 0 end)              AS denied_claims,
        ROUND(100.0 * sum(case when f.is_denied_first_pass then 1 else 0 end)
              / sum(case when NOT f.is_pending then 1 else 0 end), 2) AS denial_rate_pct,
        --SUM(f.billed_amount) WHERE f.is_denied_first_pass  AS denied_charges,
		sum(case when f.is_denied_first_pass then f.billed_amount else 0 end) AS denied_charges,
        SUM(f.revenue_at_risk)                                      AS revenue_at_risk
    FROM marts.fct_claim f
    JOIN raw.providers pr ON pr.provider_id = f.provider_id
    GROUP BY pr.provider_id, pr.provider_name, pr.specialty,
             pr.provider_type, pr.network_status
    HAVING COUNT(*) >= 50          -- exclude low-volume noise
),
benchmarked AS (
    SELECT
        pm.*,
        ROUND(AVG(denial_rate_pct) OVER (PARTITION BY specialty), 2)   AS specialty_avg_pct,
        ROUND(denial_rate_pct
              - AVG(denial_rate_pct) OVER (PARTITION BY specialty), 2) AS pts_above_peers,
        -- quartile within the whole provider network (1 = worst)
        NTILE(4) OVER (ORDER BY denial_rate_pct DESC)                  AS denial_quartile,
        DENSE_RANK() OVER (PARTITION BY specialty
                           ORDER BY denial_rate_pct DESC)              AS rank_in_specialty
    FROM provider_metrics pm
)
SELECT
    provider_name,
    specialty,
    network_status,
    total_claims,
    denial_rate_pct,
    specialty_avg_pct,
    pts_above_peers,
    rank_in_specialty,
    denial_quartile,
    CASE
        WHEN pts_above_peers >= 15 THEN 'Tier 1 - immediate audit'
        WHEN pts_above_peers >=  8 THEN 'Tier 2 - targeted education'
        WHEN pts_above_peers >=  3 THEN 'Tier 3 - monitor'
        ELSE                            'At or below peer average'
    END                                                    AS intervention_tier,
    denied_charges,
    revenue_at_risk
FROM benchmarked 
--WHERE pts_above_peers > 0
ORDER BY pts_above_peers DESC
--LIMIT 20;
