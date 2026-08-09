-- =====================================================================
-- 02_load_data.sql
-- Loads the generated CSVs into the raw layer.
--
-- Run from the PROJECT ROOT with psql so that the relative paths resolve:
--     psql -d claims_db -f sql/01_schema/02_load_data.sql
--
-- \copy runs client-side, so it needs no superuser rights (unlike COPY).
-- Load order matters: parents before children (foreign keys).
-- =====================================================================

\copy raw.denial_codes (carc_code, denial_reason, denial_category, is_preventable, typical_owner) FROM 'data/csv/denial_codes.csv' WITH (FORMAT csv, HEADER true);

\copy raw.payers (payer_id, payer_name, payer_type, state) FROM 'data/csv/payers.csv' WITH (FORMAT csv, HEADER true);

\copy raw.members (member_id, birth_date, gender, state, plan_type, enrollment_start, enrollment_end) FROM 'data/csv/members.csv' WITH (FORMAT csv, HEADER true, NULL '');

\copy raw.providers (provider_id, npi, provider_name, specialty, provider_type, state, network_status) FROM 'data/csv/providers.csv' WITH (FORMAT csv, HEADER true);

\copy raw.claims (claim_id, member_id, provider_id, payer_id, claim_type, place_of_service, service_from_date, service_to_date, submission_date, billed_amount, allowed_amount, is_resubmission) FROM 'data/csv/claims.csv' WITH (FORMAT csv, HEADER true);

\copy raw.claim_lines (claim_line_id, claim_id, line_number, procedure_code, procedure_desc, diagnosis_code, units, billed_amount, allowed_amount) FROM 'data/csv/claim_lines.csv' WITH (FORMAT csv, HEADER true);

\copy raw.remittances (remit_id, claim_id, remit_seq, remit_date, remit_status, paid_amount, adjustment_amount, carc_code) FROM 'data/csv/remittances.csv' WITH (FORMAT csv, HEADER true, NULL '');

ANALYZE;
