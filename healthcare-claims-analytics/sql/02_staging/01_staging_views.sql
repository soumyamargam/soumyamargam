-- =====================================================================
-- 01_staging_views.sql
-- Staging layer: light cleaning and business naming on top of raw.
-- No business logic yet - that lives in the marts layer.
-- =====================================================================

-- Single source of truth for the reporting cut-off, so every downstream
-- object ages A/R against the same date.
CREATE OR REPLACE VIEW staging.stg_reporting_config AS
SELECT DATE '2024-12-31' AS reporting_date;

-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW staging.stg_claims AS
SELECT
    c.claim_id,
    c.member_id,
    c.provider_id,
    c.payer_id,
    c.claim_type,
    c.place_of_service,
    c.service_from_date,
    c.service_to_date,
    c.submission_date,
    c.billed_amount,
    c.allowed_amount,
    -- lag between care delivered and claim submitted: a front-end KPI
    (c.submission_date - c.service_to_date)             AS days_to_submit,
    DATE_TRUNC('month', c.service_from_date)::date      AS service_month,
    DATE_TRUNC('month', c.submission_date)::date        AS submission_month
FROM raw.claims c;

-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW staging.stg_remittances AS
SELECT
    r.remit_id,
    r.claim_id,
    r.remit_seq,
    r.remit_date,
    r.remit_status,
    r.paid_amount,
    r.adjustment_amount,
    r.carc_code,
    (r.remit_status = 'Denied')                    AS is_denial,
    ROW_NUMBER() OVER (PARTITION BY r.claim_id
                       ORDER BY r.remit_seq)       AS remit_rank,
    COUNT(*)     OVER (PARTITION BY r.claim_id)    AS total_remits
FROM raw.remittances r;

-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW staging.stg_claim_lines AS
SELECT
    l.claim_line_id,
    l.claim_id,
    l.line_number,
    l.procedure_code,
    l.procedure_desc,
    l.diagnosis_code,
    l.units,
    l.billed_amount,
    l.allowed_amount,
    (l.billed_amount - l.allowed_amount)           AS contractual_adjustment
FROM raw.claim_lines l;
