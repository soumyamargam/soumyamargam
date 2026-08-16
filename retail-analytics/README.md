# Retail Analytics — Customer, Product & Revenue Intelligence

An end-to-end SQL analytics project on an omnichannel specialty retailer
("Northwind Threads") selling apparel, footwear, accessories, homeware and tech
across 11 physical stores and an online channel, 2023–2024.

The project takes raw transactional data through a layered
`raw → staging → marts` pipeline and answers the questions a retail analytics
team actually gets asked: *Who are our best customers? What should we stock and
discount? Are we keeping the customers we acquire? Which stores and channels
perform? What sells together?*

**All SQL is standard PostgreSQL and every query was executed against a real
database — the numbers below are actual query output, not illustrations.**
100% synthetic data; no real customer information.

---

## Headline findings

- **$6.57M** revenue across **20,625** orders from **6,000** customers, at a
  **50.3%** gross margin and a **$318** average order value.
- **The top RFM segment ("Champions") is 24% of customers but drives 63% of
  revenue.** Losing a small cohort would cost the business disproportionately —
  a clear retention priority.
- **Gold loyalty members generate ~20× the revenue per customer of Bronze**
  ($5,851 vs $293), which quantifies what the loyalty programme is worth.
- **Homeware and Tech are bought together 1.96× more than chance** (a "home
  refresh" basket), while apparel and tech rarely combine — actionable for
  cross-sell and store layout.
- **Accessories is the margin engine at 62%** even though Footwear leads on
  revenue; a revenue-only view would hide where the profit actually is.
- **Online carries a 12% return rate vs 6% in-store**, a real cost that offsets
  its higher order volume.

---

## What the project demonstrates

| Skill | Where |
|---|---|
| Layered data modelling (raw → staging → marts) | `sql/01`–`sql/03` |
| Window functions (RANK, NTILE, LAG, running totals, moving averages) | throughout `sql/04` |
| **RFM customer segmentation** | `sql/03_marts/01_fct_customer_rfm.sql` |
| **Cohort retention analysis** | `sql/04_analysis/03_cohort_retention.sql` |
| **Market-basket / association analysis** (support, confidence, lift) | `sql/04_analysis/05_market_basket.sql` |
| Pareto (80/20) analysis | `sql/04_analysis/02_product_performance.sql` |
| Margin & profitability analysis | `sql/04_analysis/02` and `04` |
| Within-group benchmarking | `sql/04_analysis/04_store_channel.sql` |
| A 20-check data-quality test suite | `sql/05_tests/` |

---

## Repository structure

```
retail-analytics/
├── README.md
├── data/
│   └── generate_retail_data.py       deterministic synthetic data generator (SEED=42)
├── load_data.py                      no-psql Python loader (COPY FROM STDIN)
├── sql/
│   ├── 01_schema/
│   │   ├── 01_create_schema.sql      raw/staging/marts schemas, 5 tables, FKs, indexes
│   │   ├── 02_load_data.sql          \copy loaders (psql)
│   │   └── 02b_load_data_server_side.sql   COPY loaders (no psql)
│   ├── 02_staging/
│   │   └── 01_staging_views.sql      cleaned, enriched views + order economics
│   ├── 03_marts/
│   │   └── 01_fct_customer_rfm.sql   CORE: one row per customer with RFM segment
│   ├── 04_analysis/
│   │   ├── 01_executive_kpis.sql     KPIs + monthly trend (LAG, rolling avg)
│   │   ├── 02_product_performance.sql category scorecard + product Pareto
│   │   ├── 03_cohort_retention.sql   acquisition cohorts and retention curves
│   │   ├── 04_store_channel.sql      store scorecard, channel + region comparison
│   │   └── 05_market_basket.sql      category affinity: support, confidence, lift
│   └── 05_tests/
│       └── data_quality_checks.sql   20 assertions, all PASS on a clean build
└── docs/
    └── metric_definitions.md         every metric defined + business glossary
```

---

## How to run it

```bash
# 1. Create the database
createdb retail_db

# 2. Generate the synthetic dataset (~1 second, deterministic)
python data/generate_retail_data.py

# 3. Build schema and load
psql -d retail_db -f sql/01_schema/01_create_schema.sql
psql -d retail_db -f sql/01_schema/02_load_data.sql

# 4. Build staging + marts
psql -d retail_db -f sql/02_staging/01_staging_views.sql
psql -d retail_db -f sql/03_marts/01_fct_customer_rfm.sql

# 5. Verify data quality — expect 20/20 PASS
psql -d retail_db -f sql/05_tests/data_quality_checks.sql

# 6. Run any analysis
psql -d retail_db -f sql/04_analysis/03_cohort_retention.sql
```

Full pipeline builds in **under 5 seconds** on a laptop.

### No psql? (pgAdmin / DBeaver users)

The `.sql` files run in any client. The only step needing psql is the CSV load,
because `02_load_data.sql` uses the psql-only `\copy`. Instead:

- **Python loader (recommended):** after `01_create_schema.sql`, set your
  connection string and run `python load_data.py`. It streams the CSVs with
  `COPY … FROM STDIN` — no psql, no server-side file access, local or remote.
- **Server-side SQL:** run `sql/01_schema/02b_load_data_server_side.sql` after
  editing the `{DIR}` placeholder to the CSV folder path (CSVs must be on the
  server; role needs file-read rights).
- **pgAdmin wizard:** right-click each `raw.*` table → *Import/Export Data* →
  Import with Header = On. Load parents first: stores, products, customers,
  orders, order_items. For `orders`, set the NULL string to empty.

---

## Data model

Five raw tables:

- **stores** (12) — physical stores + one Online "store"; dimension
- **products** (203) — catalogue with cost and list price; dimension
- **customers** (6,000) — with loyalty tier and signup; dimension
- **orders** (20,625) — one row per order (header); fact
- **order_items** (55,986) — one row per product per order (detail); fact

See `docs/metric_definitions.md` for full column meanings, and the accompanying
**Source Data Dictionary** for a table-by-table walkthrough with example rows.

---

## Data quality

The pipeline ships with a 20-assertion test suite covering referential
integrity, value ranges, business rules (e.g. returned orders must have a return
date), and financial reconciliation (staging revenue and RFM lifetime value both
reconcile penny-exact to the raw line items). On a clean build, **20/20 PASS**.

---

## Note on the data

All data is synthetically generated and fully deterministic (fixed random seed),
so anyone who clones this repo and runs the generator reproduces these exact
numbers. No real people, transactions, or company data are involved.
