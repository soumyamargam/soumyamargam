-- =====================================================================
-- 01_create_schema.sql
-- Healthcare Claims Analytics - raw (landing) layer
-- Models a payer/provider revenue-cycle feed:
--   claims (837) -> adjudication events (835 remittance) -> denials (CARC)
-- =====================================================================

DROP SCHEMA IF EXISTS raw CASCADE;
DROP SCHEMA IF EXISTS staging CASCADE;
DROP SCHEMA IF EXISTS marts CASCADE;

CREATE SCHEMA raw;
CREATE SCHEMA staging;
CREATE SCHEMA marts;

-- ---------------------------------------------------------------------
-- Reference: CARC denial reason codes
-- (Claim Adjustment Reason Codes used on 835 remittance advice)
-- ---------------------------------------------------------------------
CREATE TABLE raw.denial_codes (
    carc_code        VARCHAR(10)  PRIMARY KEY,
    denial_reason    VARCHAR(120) NOT NULL,
    denial_category  VARCHAR(40)  NOT NULL,
    is_preventable   BOOLEAN      NOT NULL,
    typical_owner    VARCHAR(40)  NOT NULL
);

-- ---------------------------------------------------------------------
-- Dimensions
-- ---------------------------------------------------------------------
CREATE TABLE raw.payers (
    payer_id     INTEGER      PRIMARY KEY,
    payer_name   VARCHAR(60)  NOT NULL,
    payer_type   VARCHAR(20)  NOT NULL,   -- Commercial / Medicare / Medicaid
    state        VARCHAR(2)   NOT NULL
);

CREATE TABLE raw.members (
    member_id        INTEGER      PRIMARY KEY,
    birth_date       DATE         NOT NULL,
    gender           VARCHAR(1)   NOT NULL,
    state            VARCHAR(2)   NOT NULL,
    plan_type        VARCHAR(20)  NOT NULL,   -- HMO / PPO / EPO / POS
    enrollment_start DATE         NOT NULL,
    enrollment_end   DATE                     -- NULL = still active
);

CREATE TABLE raw.providers (
    provider_id     INTEGER      PRIMARY KEY,
    npi             VARCHAR(10)  NOT NULL,
    provider_name   VARCHAR(80)  NOT NULL,
    specialty       VARCHAR(40)  NOT NULL,
    provider_type   VARCHAR(20)  NOT NULL,   -- Professional / Facility
    state           VARCHAR(2)   NOT NULL,
    network_status  VARCHAR(15)  NOT NULL    -- In-Network / Out-of-Network
);

-- ---------------------------------------------------------------------
-- Claim header: one row per submitted claim
-- ---------------------------------------------------------------------
CREATE TABLE raw.claims (
    claim_id           BIGINT       PRIMARY KEY,
    member_id          INTEGER      NOT NULL REFERENCES raw.members(member_id),
    provider_id        INTEGER      NOT NULL REFERENCES raw.providers(provider_id),
    payer_id           INTEGER      NOT NULL REFERENCES raw.payers(payer_id),
    claim_type         VARCHAR(20)  NOT NULL,   -- Professional / Institutional
    place_of_service   VARCHAR(30)  NOT NULL,
    service_from_date  DATE         NOT NULL,
    service_to_date    DATE         NOT NULL,
    submission_date    DATE         NOT NULL,
    billed_amount      NUMERIC(12,2) NOT NULL,
    allowed_amount     NUMERIC(12,2) NOT NULL,
    is_resubmission    BOOLEAN      NOT NULL DEFAULT FALSE
);

-- ---------------------------------------------------------------------
-- Claim line detail: one row per service line (CPT)
-- ---------------------------------------------------------------------
CREATE TABLE raw.claim_lines (
    claim_line_id   BIGINT        PRIMARY KEY,
    claim_id        BIGINT        NOT NULL REFERENCES raw.claims(claim_id),
    line_number     INTEGER       NOT NULL,
    procedure_code  VARCHAR(10)   NOT NULL,
    procedure_desc  VARCHAR(80)   NOT NULL,
    diagnosis_code  VARCHAR(10)   NOT NULL,
    units           INTEGER       NOT NULL,
    billed_amount   NUMERIC(12,2) NOT NULL,
    allowed_amount  NUMERIC(12,2) NOT NULL
);

-- ---------------------------------------------------------------------
-- Remittance / adjudication events: one row per payer response.
-- A claim denied on the first pass and later paid on appeal has TWO rows.
-- remit_seq = 1 is the first-pass response (drives first-pass KPIs).
-- ---------------------------------------------------------------------
CREATE TABLE raw.remittances (
    remit_id          BIGINT        PRIMARY KEY,
    claim_id          BIGINT        NOT NULL REFERENCES raw.claims(claim_id),
    remit_seq         INTEGER       NOT NULL,
    remit_date        DATE          NOT NULL,
    remit_status      VARCHAR(20)   NOT NULL,   -- Paid / Denied
    paid_amount       NUMERIC(12,2) NOT NULL,
    adjustment_amount NUMERIC(12,2) NOT NULL,
    carc_code         VARCHAR(10)   REFERENCES raw.denial_codes(carc_code),
    CONSTRAINT uq_remit UNIQUE (claim_id, remit_seq)
);

CREATE INDEX idx_claims_payer      ON raw.claims(payer_id);
CREATE INDEX idx_claims_provider   ON raw.claims(provider_id);
CREATE INDEX idx_claims_submission ON raw.claims(submission_date);
CREATE INDEX idx_remit_claim       ON raw.remittances(claim_id);
CREATE INDEX idx_lines_claim       ON raw.claim_lines(claim_id);
