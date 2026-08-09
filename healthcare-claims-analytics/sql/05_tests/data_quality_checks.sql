-- =====================================================================
-- data_quality_checks.sql
-- Assertion-style test suite. Every check returns a row with a PASS/FAIL
-- verdict, so the whole file can be run as one statement and eyeballed
-- in seconds (or wired into CI and failed on any FAIL).
--
-- Run:  psql -d claims_db -f sql/05_tests/data_quality_checks.sql
-- =====================================================================

WITH checks AS (

    -- 1. Every claim must belong to a real member, provider and payer
    SELECT 'Referential: claims -> members'  AS check_name,
           COUNT(*) AS failing_rows
    FROM raw.claims c
    LEFT JOIN raw.members m ON m.member_id = c.member_id
    WHERE m.member_id IS NULL

    UNION ALL
    SELECT 'Referential: claims -> providers',
           COUNT(*)
    FROM raw.claims c
    LEFT JOIN raw.providers p ON p.provider_id = c.provider_id
    WHERE p.provider_id IS NULL

    UNION ALL
    SELECT 'Referential: remittances -> claims',
           COUNT(*)
    FROM raw.remittances r
    LEFT JOIN raw.claims c ON c.claim_id = r.claim_id
    WHERE c.claim_id IS NULL

    -- 2. Uniqueness of the fact grain
    UNION ALL
    SELECT 'Uniqueness: one row per claim in fct_claim',
           COUNT(*)
    FROM (SELECT claim_id FROM marts.fct_claim
          GROUP BY claim_id HAVING COUNT(*) > 1) d

    UNION ALL
    SELECT 'Uniqueness: no duplicate remit_seq per claim',
           COUNT(*)
    FROM (SELECT claim_id, remit_seq FROM raw.remittances
          GROUP BY claim_id, remit_seq HAVING COUNT(*) > 1) d

    -- 3. Financial sanity
    UNION ALL
    SELECT 'Amounts: no negative billed amounts',
           COUNT(*) FROM raw.claims WHERE billed_amount < 0

    UNION ALL
    SELECT 'Amounts: allowed never exceeds billed',
           COUNT(*) FROM raw.claims WHERE allowed_amount > billed_amount

    UNION ALL
    SELECT 'Amounts: paid never exceeds allowed (paid claims)',
           COUNT(*)
    FROM marts.fct_claim
    WHERE is_paid_final AND final_paid_amount > allowed_amount + 0.01

    UNION ALL
    SELECT 'Amounts: denied claims carry zero payment',
           COUNT(*)
    FROM raw.remittances
    WHERE remit_status = 'Denied' AND paid_amount <> 0

    -- 4. Date logic
    UNION ALL
    SELECT 'Dates: service_to on/after service_from',
           COUNT(*) FROM raw.claims WHERE service_to_date < service_from_date

    UNION ALL
    SELECT 'Dates: submitted on/after service end',
           COUNT(*) FROM raw.claims WHERE submission_date < service_to_date

    UNION ALL
    SELECT 'Dates: remittance never precedes submission',
           COUNT(*)
    FROM raw.remittances r
    JOIN raw.claims c ON c.claim_id = r.claim_id
    WHERE r.remit_date < c.submission_date

    -- 5. Business-rule integrity
    UNION ALL
    SELECT 'Logic: every denial carries a CARC code',
           COUNT(*)
    FROM raw.remittances
    WHERE remit_status = 'Denied' AND carc_code IS NULL

    UNION ALL
    SELECT 'Logic: paid remittances carry no CARC code',
           COUNT(*)
    FROM raw.remittances
    WHERE remit_status = 'Paid' AND carc_code IS NOT NULL

    UNION ALL
    SELECT 'Logic: CARC codes exist in reference table',
           COUNT(*)
    FROM raw.remittances r
    LEFT JOIN raw.denial_codes d ON d.carc_code = r.carc_code
    WHERE r.carc_code IS NOT NULL AND d.carc_code IS NULL

    UNION ALL
    SELECT 'Logic: pending claims have no remittance',
           COUNT(*)
    FROM marts.fct_claim f
    WHERE f.is_pending
      AND EXISTS (SELECT 1 FROM raw.remittances r WHERE r.claim_id = f.claim_id)

    UNION ALL
    SELECT 'Logic: overturned implies denied first pass',
           COUNT(*)
    FROM marts.fct_claim
    WHERE is_overturned AND NOT is_denied_first_pass

    -- 6. Completeness
    UNION ALL
    SELECT 'Completeness: fct_claim row count matches raw.claims',
           ABS((SELECT COUNT(*) FROM marts.fct_claim)
             - (SELECT COUNT(*) FROM raw.claims))

    UNION ALL
    SELECT 'Completeness: every claim has at least one line',
           COUNT(*)
    FROM raw.claims c
    WHERE NOT EXISTS (SELECT 1 FROM raw.claim_lines l WHERE l.claim_id = c.claim_id)
)
SELECT
    check_name,
    failing_rows,
    CASE WHEN failing_rows = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM checks
ORDER BY (failing_rows > 0) DESC, check_name;
