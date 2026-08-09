# KPI Definitions

Every metric used in this project, with its formula and why it matters.
Definitions are deliberately explicit: most disagreements about "our denial rate"
are really disagreements about the denominator.

---

### First-Pass Denial Rate
**Formula:** claims denied on the first remittance ÷ claims that received any response
**Why it matters:** the purest measure of whether claims go out clean. Excludes
still-pending claims from the denominator — including them understates the rate
and makes the number drift as the backlog clears.

### Clean Claim Rate
**Formula:** claims paid on the first remittance ÷ claims adjudicated
**Why it matters:** the positive mirror of first-pass denial rate. Industry
benchmarks typically target 85–95%.

### Denial Overturn Rate
**Formula:** claims denied first pass but ultimately paid ÷ claims denied first pass
**Why it matters:** a *high* overturn rate is not good news. It means the denials
were wrong in the first place — the claim was payable all along, and the money
only arrived after avoidable rework.

### Net Collection Rate
**Formula:** total paid ÷ total allowed
**Why it matters:** measures collection against what the contract entitled you to,
not against list price. The realistic ceiling metric.

### Gross Collection Rate
**Formula:** total paid ÷ total billed
**Why it matters:** heavily distorted by charge-master pricing; included only for
contrast with net collection rate.

### Days to Payment
**Formula:** final payment date − submission date
**Why it matters:** direct driver of cash flow. Segment by payer to expose slow payers.

### Days to First Response
**Formula:** first remittance date − submission date
**Why it matters:** separates *payer* slowness from *our own* appeal-cycle slowness.

### A/R Aging Buckets
**Formula:** reporting date − submission date, for claims with no response, banded
0–30 / 31–60 / 61–90 / 91–120 / 120+
**Why it matters:** claims past 90 days approach timely-filing limits, after which
the revenue is permanently unrecoverable.

### Revenue at Risk
**Formula:** allowed amount on all claims not finally paid
**Why it matters:** converts operational failure into the number finance reacts to.

### Preventable Denial Rate
**Formula:** denials with a preventable CARC code ÷ all denials
**Why it matters:** separates denials caused by internal process failure
(eligibility not checked, authorization not obtained, information missing) from
legitimate clinical or contractual disputes. Only the former is fixable by
process change.

---

## CARC codes used

| Code | Reason | Category | Preventable | Owner |
|---|---|---|---|---|
| 16 | Lacks information needed for adjudication | Missing Information | Yes | Front-End Registration |
| 18 | Exact duplicate claim/service | Billing Error | Yes | Billing |
| 27 | Expenses incurred after coverage terminated | Eligibility | Yes | Front-End Registration |
| 29 | Time limit for filing has expired | Timely Filing | Yes | Billing |
| 50 | Not deemed a medical necessity | Medical Necessity | No | Clinical Documentation |
| 96 | Non-covered charge(s) | Benefits | No | Contracting |
| 97 | Benefit included in payment for another service | Bundling | No | Coding |
| 109 | Claim not covered by this payer | Wrong Payer | Yes | Front-End Registration |
| 119 | Benefit maximum reached | Benefits | No | Contracting |
| 197 | Precertification/authorization absent | Prior Authorization | Yes | Utilization Mgmt |
| 252 | Attachment/documentation required | Missing Information | Yes | Clinical Documentation |

CARC (Claim Adjustment Reason Code) is the standard code set transmitted on the
835 electronic remittance advice to explain why a claim was adjusted or denied.
