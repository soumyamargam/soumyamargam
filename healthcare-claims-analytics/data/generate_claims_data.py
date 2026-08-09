"""
generate_claims_data.py
-----------------------
Generates a realistic, fully synthetic healthcare claims dataset for the
Healthcare Claims Analytics project.

No real patient data is used or required - every record is fabricated, so the
repository is safe to publish publicly (no PHI / HIPAA exposure).

Run:  python data/generate_claims_data.py
Out:  data/csv/*.csv
"""

import csv
import os
import random
from datetime import date, timedelta

SEED = 42                      # deterministic: same data on every run
N_MEMBERS = 4_000
N_PROVIDERS = 300
N_CLAIMS = 60_000
START_DATE = date(2023, 1, 1)
END_DATE = date(2024, 12, 31)

random.seed(SEED)
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "csv")
os.makedirs(OUT_DIR, exist_ok=True)


def write_csv(name, header, rows):
    path = os.path.join(OUT_DIR, name)
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)
    print(f"  {name:<22} {len(rows):>7,} rows")


# ---------------------------------------------------------------------
# 1. Reference data - real CARC denial codes
# ---------------------------------------------------------------------
DENIAL_CODES = [
    # code, reason, category, preventable, owner
    ("16",  "Claim/service lacks information needed for adjudication", "Missing Information", True,  "Front-End Registration"),
    ("18",  "Exact duplicate claim/service",                            "Billing Error",       True,  "Billing"),
    ("27",  "Expenses incurred after coverage terminated",              "Eligibility",         True,  "Front-End Registration"),
    ("29",  "The time limit for filing has expired",                    "Timely Filing",       True,  "Billing"),
    ("50",  "Not deemed a medical necessity by the payer",              "Medical Necessity",   False, "Clinical Documentation"),
    ("96",  "Non-covered charge(s)",                                    "Benefits",            False, "Contracting"),
    ("97",  "Benefit included in payment for another service",          "Bundling",            False, "Coding"),
    ("109", "Claim not covered by this payer/contractor",               "Wrong Payer",         True,  "Front-End Registration"),
    ("119", "Benefit maximum for this period has been reached",         "Benefits",            False, "Contracting"),
    ("197", "Precertification/authorization absent",                    "Prior Authorization", True,  "Utilization Mgmt"),
    ("252", "An attachment/other documentation is required",            "Missing Information", True,  "Clinical Documentation"),
]
# Relative likelihood of each denial reason (mirrors published RCM benchmarks:
# authorization + missing information + eligibility dominate)
DENIAL_WEIGHTS = [22, 6, 9, 5, 11, 8, 7, 6, 3, 18, 5]

write_csv(
    "denial_codes.csv",
    ["carc_code", "denial_reason", "denial_category", "is_preventable", "typical_owner"],
    [(c, r, cat, str(p).lower(), o) for c, r, cat, p, o in DENIAL_CODES],
)

# ---------------------------------------------------------------------
# 2. Payers - each with its own behaviour profile
# ---------------------------------------------------------------------
PAYERS = [
    # id, name, type, state, denial_rate, avg_pay_lag, overturn_rate, allowed_pct
    (1, "Meridian Health Plan",   "Commercial", "MI", 0.115, 24, 0.62, 0.68),
    (2, "BlueRidge PPO",          "Commercial", "NC", 0.092, 19, 0.68, 0.72),
    (3, "Statewide Medicaid",     "Medicaid",   "MI", 0.168, 38, 0.48, 0.55),
    (4, "National Medicare Adv.", "Medicare",   "TX", 0.104, 21, 0.58, 0.63),
    (5, "Summit Choice HMO",      "Commercial", "OH", 0.134, 29, 0.55, 0.66),
    (6, "Great Lakes Mutual",     "Commercial", "IL", 0.078, 17, 0.71, 0.74),
]
write_csv("payers.csv", ["payer_id", "payer_name", "payer_type", "state"],
          [(p[0], p[1], p[2], p[3]) for p in PAYERS])
PAYER_PROFILE = {p[0]: {"denial": p[4], "lag": p[5], "overturn": p[6], "allowed": p[7]} for p in PAYERS}

# ---------------------------------------------------------------------
# 3. Members
# ---------------------------------------------------------------------
STATES = ["MI", "NC", "TX", "OH", "IL", "IN"]
PLANS = ["HMO", "PPO", "EPO", "POS"]
members = []
for mid in range(1, N_MEMBERS + 1):
    birth = date(1940, 1, 1) + timedelta(days=random.randint(0, 24000))
    enr_start = START_DATE - timedelta(days=random.randint(0, 900))
    # ~6% of members terminate coverage during the window -> drives CARC 27
    enr_end = ""
    if random.random() < 0.06:
        enr_end = (START_DATE + timedelta(days=random.randint(120, 700))).isoformat()
    members.append((mid, birth.isoformat(), random.choice("MF"),
                    random.choice(STATES), random.choice(PLANS),
                    enr_start.isoformat(), enr_end))
write_csv("members.csv",
          ["member_id", "birth_date", "gender", "state", "plan_type", "enrollment_start", "enrollment_end"],
          members)
MEMBER_TERM = {m[0]: (date.fromisoformat(m[6]) if m[6] else None) for m in members}

# ---------------------------------------------------------------------
# 4. Providers - a few deliberate underperformers for the analysis to find
# ---------------------------------------------------------------------
SPECIALTIES = [
    "Family Medicine", "Internal Medicine", "Cardiology", "Orthopedics",
    "Radiology", "Emergency Medicine", "General Surgery", "Dermatology",
    "Behavioral Health", "Physical Therapy",
]
LAST = ["Whitmore", "Alvarez", "Chen", "Okafor", "Nguyen", "Patel", "Rossi", "Kim",
        "Fischer", "Dubois", "Haddad", "Silva", "Novak", "Ivanov", "Murphy"]
FIRST = ["Grace", "Daniel", "Priya", "Marcus", "Elena", "Omar", "Sofia", "Ethan",
         "Nadia", "Liam", "Ruth", "Andre", "Maya", "Victor", "Iris"]

providers = []
PROV_PROFILE = {}
for pid in range(1, N_PROVIDERS + 1):
    ptype = "Facility" if random.random() < 0.22 else "Professional"
    name = (f"{random.choice(FIRST)} {random.choice(LAST)}, MD"
            if ptype == "Professional"
            else f"{random.choice(['Lakeside', 'Summit', 'Riverbend', 'Cedar Park', 'Northgate'])} "
                 f"{random.choice(['Medical Center', 'Regional Hospital', 'Surgery Center'])}")
    network = "Out-of-Network" if random.random() < 0.13 else "In-Network"
    # multiplier applied to the payer's base denial rate
    modifier = random.gauss(1.0, 0.22)
    if pid <= 8:                       # 8 chronically poor performers
        modifier = random.uniform(1.9, 2.6)
    modifier = max(0.35, min(3.0, modifier))
    providers.append((pid, str(1000000000 + pid * 7919)[:10], name,
                      random.choice(SPECIALTIES), ptype,
                      random.choice(STATES), network))
    PROV_PROFILE[pid] = modifier
write_csv("providers.csv",
          ["provider_id", "npi", "provider_name", "specialty", "provider_type", "state", "network_status"],
          providers)

# ---------------------------------------------------------------------
# 5. Procedures
# ---------------------------------------------------------------------
PROCEDURES = [
    ("99213", "Office visit, established patient, 20-29 min",  140),
    ("99214", "Office visit, established patient, 30-39 min",  210),
    ("99203", "Office visit, new patient, 30-44 min",          260),
    ("99284", "Emergency dept visit, moderate complexity",     890),
    ("70450", "CT head/brain without contrast",                640),
    ("72148", "MRI lumbar spine without contrast",            1180),
    ("73721", "MRI joint lower extremity without contrast",   1050),
    ("29881", "Knee arthroscopy with meniscectomy",           4200),
    ("47562", "Laparoscopic cholecystectomy",                 7800),
    ("93000", "Electrocardiogram, complete",                    75),
    ("80053", "Comprehensive metabolic panel",                   48),
    ("85025", "Complete blood count with differential",          36),
    ("97110", "Therapeutic exercise, each 15 min",              105),
    ("90837", "Psychotherapy, 60 min",                          195),
    ("11042", "Debridement, subcutaneous tissue",               380),
]
DIAGNOSES = ["E11.9", "I10", "M54.5", "J06.9", "Z00.00", "F41.1", "M17.11",
             "K80.20", "R07.9", "N39.0", "J45.909", "I25.10"]
POS = ["Office", "Outpatient Hospital", "Inpatient Hospital",
       "Emergency Room", "Telehealth", "Ambulatory Surgical Center"]

# ---------------------------------------------------------------------
# 6. Claims, lines and remittance events
# ---------------------------------------------------------------------
claims, lines, remits = [], [], []
claim_id, line_id, remit_id = 100_000, 500_000, 900_000
total_days = (END_DATE - START_DATE).days

for _ in range(N_CLAIMS):
    claim_id += 1
    member_id = random.randint(1, N_MEMBERS)
    provider_id = random.randint(1, N_PROVIDERS)
    payer_id = random.choice([1, 1, 2, 2, 3, 3, 4, 5, 6])   # uneven payer mix
    prof = PAYER_PROFILE[payer_id]

    svc_from = START_DATE + timedelta(days=random.randint(0, total_days))
    svc_to = svc_from + timedelta(days=random.choice([0, 0, 0, 1, 2]))
    submit = svc_to + timedelta(days=random.randint(1, 21))

    ptype = providers[provider_id - 1][4]
    claim_type = "Institutional" if ptype == "Facility" else "Professional"
    pos = random.choice(POS)

    n_lines = random.choices([1, 2, 3, 4, 5], weights=[38, 27, 18, 11, 6])[0]
    claim_billed = 0.0
    claim_allowed = 0.0
    pending_lines = []
    for ln in range(1, n_lines + 1):
        code, desc, base = random.choice(PROCEDURES)
        units = 1 if base > 500 else random.choices([1, 2, 3], weights=[80, 15, 5])[0]
        billed = round(base * units * random.uniform(0.85, 1.30), 2)
        allowed = round(billed * prof["allowed"] * random.uniform(0.92, 1.05), 2)
        allowed = min(allowed, billed)
        claim_billed += billed
        claim_allowed += allowed
        line_id += 1
        pending_lines.append((line_id, claim_id, ln, code, desc,
                              random.choice(DIAGNOSES), units,
                              f"{billed:.2f}", f"{allowed:.2f}"))
    lines.extend(pending_lines)
    claim_billed = round(claim_billed, 2)
    claim_allowed = round(claim_allowed, 2)

    # ---- decide first-pass outcome -------------------------------------
    denial_rate = prof["denial"] * PROV_PROFILE[provider_id]
    if providers[provider_id - 1][6] == "Out-of-Network":
        denial_rate *= 1.35
    # gentle upward drift over time so trend analysis has a story
    months_in = (svc_from.year - 2023) * 12 + svc_from.month - 1
    denial_rate *= (1 + months_in * 0.004)
    denial_rate = max(0.02, min(0.75, denial_rate))

    term = MEMBER_TERM[member_id]
    coverage_lapsed = term is not None and svc_from > term
    if coverage_lapsed:
        denial_rate = 0.92           # service after termination -> nearly always denied

    is_denied_first = random.random() < denial_rate

    claims.append((claim_id, member_id, provider_id, payer_id, claim_type, pos,
                   svc_from.isoformat(), svc_to.isoformat(), submit.isoformat(),
                   f"{claim_billed:.2f}", f"{claim_allowed:.2f}", "false"))

    lag = max(5, int(random.gauss(prof["lag"], prof["lag"] * 0.28)))
    remit1_date = submit + timedelta(days=lag)

    # ~4% of claims are still in flight at the reporting cut-off -> AR aging
    if remit1_date > END_DATE or random.random() < 0.04:
        continue

    if not is_denied_first:
        paid = round(claim_allowed * random.uniform(0.94, 1.0), 2)
        remit_id += 1
        remits.append((remit_id, claim_id, 1, remit1_date.isoformat(), "Paid",
                       f"{paid:.2f}", f"{claim_billed - paid:.2f}", ""))
    else:
        if coverage_lapsed:
            carc = "27"
        else:
            carc = random.choices([d[0] for d in DENIAL_CODES], weights=DENIAL_WEIGHTS)[0]
        remit_id += 1
        remits.append((remit_id, claim_id, 1, remit1_date.isoformat(), "Denied",
                       "0.00", f"{claim_billed:.2f}", carc))

        # ---- appeal / rework -------------------------------------------
        preventable = dict((d[0], d[3]) for d in DENIAL_CODES)[carc]
        appeal_chance = 0.80 if preventable else 0.55
        if random.random() < appeal_chance:
            rework = random.randint(12, 55)
            remit2_date = remit1_date + timedelta(days=rework)
            if remit2_date <= END_DATE:
                overturn = prof["overturn"] * (1.12 if preventable else 0.85)
                if random.random() < min(0.92, overturn):
                    paid = round(claim_allowed * random.uniform(0.90, 1.0), 2)
                    remit_id += 1
                    remits.append((remit_id, claim_id, 2, remit2_date.isoformat(), "Paid",
                                   f"{paid:.2f}", f"{claim_billed - paid:.2f}", ""))
                else:
                    remit_id += 1
                    remits.append((remit_id, claim_id, 2, remit2_date.isoformat(), "Denied",
                                   "0.00", f"{claim_billed:.2f}", carc))

write_csv("claims.csv",
          ["claim_id", "member_id", "provider_id", "payer_id", "claim_type",
           "place_of_service", "service_from_date", "service_to_date",
           "submission_date", "billed_amount", "allowed_amount", "is_resubmission"],
          claims)
write_csv("claim_lines.csv",
          ["claim_line_id", "claim_id", "line_number", "procedure_code", "procedure_desc",
           "diagnosis_code", "units", "billed_amount", "allowed_amount"],
          lines)
write_csv("remittances.csv",
          ["remit_id", "claim_id", "remit_seq", "remit_date", "remit_status",
           "paid_amount", "adjustment_amount", "carc_code"],
          remits)

print("\nDone. Load with sql/01_schema/02_load_data.sql")
