-- =====================================================================
-- 01_fct_claim.sql
-- THE core model of the project.
--
-- Grain: one row per claim.
-- Collapses the claim's entire adjudication history (1..n remittance
-- events) into a single analysis-ready row, so every downstream question
-- is a simple aggregation instead of a re-derivation of claim logic.
--
-- Key distinction this table encodes - and the reason the project has a
-- story: a claim denied on the FIRST pass and later paid on appeal is a
-- revenue success but an operational failure. Counting only the final
-- status hides all rework cost. So we keep both.
-- =====================================================================

DROP TABLE IF EXISTS marts.fct_claim;

CREATE TABLE marts.fct_claim AS
WITH first_pass AS (
    -- The payer's first response: drives denial rate and first-pass yield
    SELECT claim_id, remit_date, remit_status, carc_code, paid_amount
    FROM raw.remittances
    WHERE remit_seq = 1
),
final_pass AS (
    -- The last response on record. DISTINCT ON is the idiomatic
    -- PostgreSQL way to take "the top row per group".
    SELECT DISTINCT ON (claim_id)
           claim_id, remit_date, remit_status, carc_code, paid_amount, remit_seq
    FROM raw.remittances
    ORDER BY claim_id, remit_seq DESC
),
remit_counts AS (
    SELECT claim_id, COUNT(*) AS remit_events
    FROM raw.remittances
    GROUP BY claim_id
)
SELECT
    c.claim_id,
    c.member_id,
    c.provider_id,
    c.payer_id,
    c.claim_type,
    c.place_of_service,
    c.service_from_date,
    c.submission_date,
    DATE_TRUNC('month', c.submission_date)::date          AS submission_month,
    c.billed_amount,
    c.allowed_amount,

    ---------------------------------------------------------------- first pass
    fp.remit_date                                          AS first_remit_date,
    fp.remit_status                                        AS first_remit_status,
    fp.carc_code                                           AS first_carc_code,
    COALESCE(rc.remit_events, 0)                           AS remit_events,

    ---------------------------------------------------------------- final state
    lp.remit_date                                          AS final_remit_date,
    lp.remit_status                                        AS final_remit_status,
    COALESCE(lp.paid_amount, 0)                            AS final_paid_amount,

    ---------------------------------------------------------------- flags
    (fp.claim_id IS NULL)                                  AS is_pending,
    COALESCE(fp.remit_status = 'Denied', FALSE)            AS is_denied_first_pass,
    COALESCE(lp.remit_status = 'Paid',   FALSE)            AS is_paid_final,
    -- denied first, paid in the end = rework that succeeded
    COALESCE(fp.remit_status = 'Denied'
             AND lp.remit_status = 'Paid', FALSE)          AS is_overturned,
    -- denied and never recovered = true lost revenue
    COALESCE(lp.remit_status = 'Denied', FALSE)            AS is_denied_final,

    ---------------------------------------------------------------- lifecycle status
    CASE
        WHEN fp.claim_id IS NULL                              THEN 'Pending / No Response'
        WHEN fp.remit_status = 'Paid'                         THEN 'Paid First Pass'
        WHEN fp.remit_status = 'Denied'
             AND lp.remit_status = 'Paid'                     THEN 'Overturned on Appeal'
        WHEN fp.remit_status = 'Denied'
             AND lp.remit_seq > 1                             THEN 'Denied After Appeal'
        ELSE                                                       'Denied - Not Appealed'
    END                                                     AS claim_outcome,

    ---------------------------------------------------------------- cycle times
    (fp.remit_date - c.submission_date)                     AS days_to_first_response,
    CASE WHEN lp.remit_status = 'Paid'
         THEN (lp.remit_date - c.submission_date) END       AS days_to_payment,

    ---------------------------------------------------------------- A/R ageing
    CASE WHEN fp.claim_id IS NULL
         THEN (cfg.reporting_date - c.submission_date) END  AS ar_days,
    CASE
        WHEN fp.claim_id IS NOT NULL                            THEN 'Adjudicated'
        WHEN cfg.reporting_date - c.submission_date <=  30      THEN '0-30 days'
        WHEN cfg.reporting_date - c.submission_date <=  60      THEN '31-60 days'
        WHEN cfg.reporting_date - c.submission_date <=  90      THEN '61-90 days'
        WHEN cfg.reporting_date - c.submission_date <= 120      THEN '91-120 days'
        ELSE                                                         '120+ days'
    END                                                     AS ar_bucket,

    ---------------------------------------------------------------- money at risk
    CASE WHEN COALESCE(lp.remit_status, 'Pending') <> 'Paid'
         THEN c.allowed_amount ELSE 0 END                   AS revenue_at_risk
FROM raw.claims c
CROSS JOIN staging.stg_reporting_config cfg
LEFT JOIN first_pass   fp ON fp.claim_id = c.claim_id
LEFT JOIN final_pass   lp ON lp.claim_id = c.claim_id
LEFT JOIN remit_counts rc ON rc.claim_id = c.claim_id;

ALTER TABLE marts.fct_claim ADD PRIMARY KEY (claim_id);
CREATE INDEX idx_fct_payer    ON marts.fct_claim(payer_id);
CREATE INDEX idx_fct_provider ON marts.fct_claim(provider_id);
CREATE INDEX idx_fct_month    ON marts.fct_claim(submission_month);
CREATE INDEX idx_fct_carc     ON marts.fct_claim(first_carc_code);

ANALYZE marts.fct_claim;
