# Healthcare Claims Denial & Revenue Cycle Analytics

An end-to-end SQL analytics project on healthcare claims data: a modelled
claims warehouse, a tested transformation layer, and an analysis suite that
answers the questions a revenue-cycle team actually asks.

**Stack:** PostgreSQL 16 · SQL (CTEs, window functions, conditional aggregation) · Python (synthetic data generation)

> **On data privacy:** this project uses **100% synthetic data**. No real patient,
> provider or payer information is used anywhere in this repository. The generator
> produces statistically realistic claims — denial-rate distributions, CARC code
> frequencies and payment lags are modelled on published industry benchmarks — so
> the analysis is meaningful without any PHI/HIPAA exposure. Run
> `python data/generate_claims_data.py` to reproduce the exact dataset (fixed seed).

---

## The business problem

When a payer denies a claim, the provider does not simply lose the money — they
lose it *twice*. Once in unrecovered revenue, and again in the staff hours spent
reworking and appealing a claim that should have gone out clean the first time.

Most claims reporting only tracks **final** status, which hides this entirely: a
claim denied on submission and paid three months later on appeal looks identical
to one paid correctly on day one. It is not. One cost nothing; the other consumed
rework capacity and delayed cash by months.

**This project separates the two,** then answers:

1. What is our true first-pass denial rate, and is it getting worse?
2. Which denial reasons drive the majority of the damage?
3. Which payers behave worst — and can we evidence it in a contract negotiation?
4. Which providers are genuine outliers *versus their own specialty peers*?
5. How much unpaid A/R is aging into timely-filing risk?
6. If we fixed only the preventable denials, what is that worth, and which team owns it?

---

## Headline findings

| Metric | Value |
|---|---|
| Claims analysed | 60,000 |
| Total billed | $166.4M |
| First-pass denial rate | **15.3%** |
| Clean claim rate | 84.7% |
| Denial overturn rate | 43.6% |
| Net collection rate | 80.9% |
| Avg. days to payment | 27.0 |
| **Revenue at risk** | **$17.8M** |

**Three findings that would change what a team does on Monday:**

- **57% of all denials come from just 3 root causes** — coverage terminated (CARC 27),
  missing information (CARC 16) and absent prior authorization (CARC 197). All three
  are *preventable* and all three are owned upstream of billing.
- **Front-End Registration alone owns $3.6M of unrecovered revenue** plus $3.4M of
  avoidable rework — making eligibility verification at check-in the single highest-ROI
  fix available.
- **$3.5M of expected value is sitting in 120+ day A/R** (37% of all open claims),
  aging toward timely-filing write-off.

---

## Architecture

```
data/generate_claims_data.py     synthetic 837/835-style claims feed
        |
        v
  raw schema        landing tables, foreign keys enforced
        |           claims · claim_lines · remittances · members · providers · payers · denial_codes
        v
  staging schema    typed & cleaned views, single reporting-date config
        |
        v
  marts schema      fct_claim — one row per claim, full lifecycle collapsed
        |
        v
  analysis layer    executive KPIs · denial Pareto · payer scorecard
                    provider outliers · A/R aging · recovery opportunity
```

### The core model: `marts.fct_claim`

The heart of the project. A claim can have several adjudication events; this table
collapses that history into one analysis-ready row per claim, preserving the
distinction that matters:

| Column | Meaning |
|---|---|
| `is_denied_first_pass` | Payer rejected the original submission (operational failure) |
| `is_overturned` | Denied first, recovered on appeal (revenue saved, rework spent) |
| `is_denied_final` | Never recovered (true lost revenue) |
| `claim_outcome` | Paid First Pass / Overturned on Appeal / Denied After Appeal / Denied - Not Appealed / Pending |
| `days_to_payment` | Submission to final payment |
| `ar_bucket` | 0-30 / 31-60 / 61-90 / 91-120 / 120+ for open claims |
| `revenue_at_risk` | Allowed amount not yet collected |

Because the claim logic lives here once, every downstream question is a simple
aggregation rather than a re-derivation — the same reason production analytics
teams build a fact layer instead of writing one-off queries.

---

## Repository structure

```
healthcare-claims-analytics/
├── data/
│   ├── generate_claims_data.py      deterministic synthetic data generator
│   └── csv/                         generated output (git-ignored)
├── sql/
│   ├── 01_schema/
│   │   ├── 01_create_schema.sql     DDL: schemas, tables, FKs, indexes
│   │   └── 02_load_data.sql         \copy loaders
│   ├── 02_staging/
│   │   └── 01_staging_views.sql     typed/cleaned views
│   ├── 03_marts/
│   │   └── 01_fct_claim.sql         core claim-grain fact table
│   ├── 04_analysis/
│   │   ├── 01_executive_kpis.sql    KPI summary + monthly trend
│   │   ├── 02_denial_pareto.sql     denial reasons + cumulative %
│   │   ├── 03_payer_scorecard.sql   payer ranking vs book average
│   │   ├── 04_provider_outliers.sql peer-benchmarked provider tiers
│   │   └── 05_ar_aging_and_opportunity.sql
│   └── 05_tests/
│       └── data_quality_checks.sql  19 assertion-style tests
└── docs/
    └── kpi_definitions.md           metric definitions & formulas
```

---

## How to run it

```bash
# 1. Create the database
createdb claims_db

# 2. Generate the synthetic dataset (~5 seconds)
python data/generate_claims_data.py

# 3. Build schema and load  (run from the project root)
psql -d claims_db -f sql/01_schema/01_create_schema.sql
psql -d claims_db -f sql/01_schema/02_load_data.sql

# 4. Build staging + marts
psql -d claims_db -f sql/02_staging/01_staging_views.sql
psql -d claims_db -f sql/03_marts/01_fct_claim.sql

# 5. Verify data quality — expect 19/19 PASS
psql -d claims_db -f sql/05_tests/data_quality_checks.sql

# 6. Run any analysis
psql -d claims_db -f sql/04_analysis/02_denial_pareto.sql
```

Full pipeline builds in **under 10 seconds** on a laptop.

---

## Data quality

Nineteen assertion-style checks run as a single statement and return `PASS`/`FAIL`
per rule — referential integrity, fact-grain uniqueness, financial sanity
(allowed never exceeds billed, denials carry zero payment), date logic
(remittance never precedes submission), and business rules (every denial carries
a valid CARC code; overturned implies denied-first-pass).

```
check_name                                           | failing_rows | status
-----------------------------------------------------+--------------+-------
Amounts: allowed never exceeds billed                | 0            | PASS
Logic: every denial carries a CARC code              | 0            | PASS
Uniqueness: one row per claim in fct_claim           | 0            | PASS
...                                                  |              |
(19 rows — all PASS)
```

---

## SQL techniques demonstrated

| Technique | Where |
|---|---|
| Window functions — `RANK`, `DENSE_RANK`, `NTILE` | payer scorecard, provider outliers |
| Running totals / Pareto — `SUM() OVER (ORDER BY ...)` | denial Pareto, A/R cumulative value |
| Moving averages — bounded `ROWS BETWEEN` frames | 3-month rolling denial rate |
| `LAG` for period-over-period change | monthly denial trend |
| Partitioned benchmarks — `AVG() OVER (PARTITION BY ...)` | provider vs specialty peers |
| `FILTER` clause for conditional aggregation | every KPI query |
| `DISTINCT ON` (PostgreSQL) | latest remittance per claim |
| CTEs for readable multi-step logic | throughout |
| `CASE` for banding & tiering | A/R buckets, intervention tiers |
| Anti-joins / `NOT EXISTS` | data quality checks |

---

## Possible extensions

- Visualise the marts layer in Power BI / Metabase / Streamlit
- Port the transformations to dbt with `schema.yml` tests
- Add a denial-prediction model scoring claims pre-submission
- Incremental loading and slowly-changing provider dimensions
