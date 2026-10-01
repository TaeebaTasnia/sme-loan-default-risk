# SME Loan Default Risk — Complete Project Explainer

> Written in plain English. No background in data science required to follow this.

---

## What Is This Project?

Imagine you work at a bank. Every day, small business owners walk in and ask for a loan. Your job is to decide: **will this person pay the loan back, or will they stop paying (default)?**

Making a wrong decision costs the bank money. So instead of guessing, we build a **model** — a set of mathematical rules learned from thousands of past loans — that looks at a new loan application and says: *"There's a 23% chance this person will default."*

That's exactly what this project does. It uses **real US government loan data** (899,000 loans over 40+ years) to train a model that predicts loan default, and wraps the results in a **dashboard** — a web page with charts and a form where you can type in a loan's details and instantly see the predicted risk.

---

## The Data

**Source:** US Small Business Administration (SBA) — a government agency that guarantees loans to small businesses.

**File:** `SBAnational.csv` — 899,000 rows, one row per loan.

**The question we're answering:** For each loan, did the borrower pay it back in full (`P I F` = Paid In Full), or did they stop paying and the loan was written off (`CHGOFF` = Charged Off / defaulted)?

**The 8 features (inputs) we use to predict:**

| Feature | What it means | Example |
|---------|---------------|---------|
| `GrAppv` | Total loan amount approved | $150,000 |
| `Term` | How many months to repay | 84 months (7 years) |
| `NAICS` | Industry code (first 2 digits = sector) | "72" = Restaurants/Hotels |
| `State` | Which US state the business is in | "CA" = California |
| `NoEmp` | Number of employees | 10 |
| `NewExist` | Is the business new (2) or existing (1)? | 1 = Existing |
| `UrbanRural` | Is it in a city (1), countryside (2), or unknown (0)? | 1 = Urban |
| `RevLineCr` | Does it have a revolving credit line? | Y or N |

**Why only 8 features?** The dataset has many more columns, but we deliberately chose only these 8 — they describe the *applicant at the time of application*, not what happened *during* the loan. Using after-the-fact data (like whether a payment was missed) would be cheating.

---

## The File Structure — What Every File Does

```
sme-loan-risk/
│
├── R/                      ← The brains. Run these in order.
│   ├── 01_data_prep.R      ← Reads and cleans the raw data
│   ├── 02_eda.R            ← Explores the data with charts
│   ├── 03_model.R          ← Builds the prediction model
│   └── 04_evaluate.R       ← Tests how good the model is
│
├── app/
│   └── app.R               ← The web dashboard (Shiny)
│
├── data/                   ← Where cleaned data files are saved (.rds)
├── models/                 ← Where the trained model is saved (.rds)
├── plots/                  ← Where chart data is saved (.rds)
│
├── docs/
│   └── terms.md            ← Plain-English glossary (WoE, IV, AUC, KS)
│
├── README.md               ← Short project summary
└── EXPLAINER.md            ← This file
```

`.rds` files are R's native save format — like a `.pkl` in Python. They're fast to load and preserve all data types exactly.

---

## Script 1 — `R/01_data_prep.R`: Cleaning the Raw Data

### What problem does it solve?

The raw CSV is messy. Dollar amounts look like `"$1,234.00"` (a text string, not a number). Dates are in a weird format. Some rows have no label (neither PIF nor CHGOFF — we can't learn from those). And 899,000 rows is slow to work with, so we take a smaller representative sample.

### What it does, step by step:

**Step 1 — Read the CSV**
```
Read 899,164 rows from SBAnational.csv
```
We tell R exactly what data type each column should be (text, number, etc.) so nothing gets misread.

**Step 2 — Clean dollar amounts**
The column `GrAppv` contains values like `"$150,000.00"`. We strip the `$` and `,` and convert to a proper number: `150000`.

**Step 3 — Filter to labelled rows only**
We keep only rows where `MIS_Status` is either `"P I F"` or `"CHGOFF"`. Rows with blank or other values can't be used for training — we don't know their outcome.

After filtering: **897,167 labelled rows.**

**Step 4 — Create the target variable**
```r
default_flag = 1   if the loan was charged off (defaulted)
default_flag = 0   if the loan was paid in full
```
This is the number the model will learn to predict.

**Step 5 — Engineer features**
- Extract the first 2 digits of `NAICS` → `naics_sector` (e.g., "722" → "72" = Food Services)
- Convert text columns to factors (R's way of saying "this is a category, not free text")

**Step 6 — Stratified sample of 30,000 rows**

Why 30,000? The full 897k rows would take too long to train on a laptop. 30,000 is large enough to learn real patterns.

**Stratified** means: if 17.6% of all loans defaulted, exactly 17.6% of our 30,000-row sample will also be defaults. We don't accidentally oversample or undersample either group.

```
Sample size: 29,999 rows | Default rate: 17.6%  ✓
```

**Step 7 — 70/30 train/test split**

We split the 30,000 rows into:
- **Train set (21,000 rows):** The model learns from these.
- **Test set (9,000 rows):** The model has NEVER seen these. We use them to check if it actually learned or just memorised.

Again stratified — both sets have the same 17.6% default rate.

**Output files:**
- `data/sba_sample_30k.rds` — full 30k sample
- `data/train.rds` — 21,000 rows for training
- `data/test.rds` — 9,000 rows for testing

---

## Script 2 — `R/02_eda.R`: Exploring the Data

EDA = **Exploratory Data Analysis**. Before building a model, a data scientist looks at the data to understand it. This script produces 4 charts and 4 summary numbers.

### The 4 KPIs (Key Performance Indicators)

| KPI | Value |
|-----|-------|
| Total loans in training set | 21,000 |
| Overall default rate | 17.6% |
| Average loan size | $192,110 |
| Average loan term | 111 months (~9 years) |

### The 4 Charts

**Chart 1 — Default rate by industry sector**
Some industries default more than others. Restaurants and construction tend to be riskier than, say, healthcare. This chart shows which NAICS sectors (by 2-digit code) have the highest default rates among the top-10 most common sectors.

**Chart 2 — Default rate by loan size**
Does borrowing more money make you more or less likely to default? Smaller loans ($0–50k) tend to default more — often taken by riskier micro-businesses with no collateral.

**Chart 3 — Default rate by state**
Geography matters. Some states have higher default rates due to economic conditions, industry mix, or local lending practices.

**Chart 4 — Default rate by approval year**
Early loans (1970s–80s) have higher default rates — partly because the SBA was newer and less selective, and partly because of economic recessions. The rate drops after the 1980s.

**Output:** `plots/eda_plots.rds` — the aggregated data for all 4 charts, used by the dashboard.

---

## Script 3 — `R/03_model.R`: Building the Model

This is the most technical script. Here's what happens in plain English.

### Step 1 — Weight of Evidence (WoE) Transformation

**The problem:** Our features are a mix of numbers (`GrAppv`, `NoEmp`) and categories (`State`, `RevLineCr`). Logistic regression expects everything to be on a comparable numeric scale.

**The solution:** WoE converts every feature — regardless of type — into a single number that represents *how much that specific value pushes the probability of default up or down*.

**Intuition:** Imagine the `State` feature. If loans in California default at exactly the overall average rate, the WoE for California is 0 (neutral). If loans in Nevada default much more than average, Nevada gets a positive WoE (pushes risk up). If loans in Texas default much less, Texas gets a negative WoE (pushes risk down).

```
WoE for a bin = log( fraction of defaults in this bin / fraction of non-defaults in this bin )
```

This is standard credit-industry practice — banks have used WoE for scorecard models for decades.

### Step 2 — Information Value (IV) Filter

After computing WoE bins, we compute **Information Value** for each feature — a single number summarising how useful the entire feature is for predicting default.

```
IV < 0.02  → useless (no predictive signal) → DROP
IV 0.02–0.5 → useful → KEEP
IV > 0.5   → suspiciously perfect → likely data leakage → DROP
```

**PAUSE:** The script prints the IV table and waits for you to press Enter before dropping anything. This is intentional — a data scientist should always review this table manually.

**Our IV results:**

| Feature | IV | Decision |
|---------|-----|---------|
| Term | 4.65 | **DROPPED** — IV > 0.5, suspected leakage |
| GrAppv | 0.52 | **DROPPED** — IV > 0.5 |
| UrbanRural | 0.39 | Kept ✓ |
| naics_sector | 0.24 | Kept ✓ |
| NoEmp | 0.15 | Kept ✓ |
| State | 0.15 | Kept ✓ |
| RevLineCr | 0.14 | Kept ✓ |
| NewExist | 0.003 | **DROPPED** — IV < 0.02, no signal |

Why was `Term` dropped at IV=4.65? Because loan term is often set *after* the bank already assessed default risk — it's partly determined by the outcome we're trying to predict. Using it would be circular reasoning.

### Step 3 — Logistic Regression

We fit a logistic regression on the 5 surviving WoE-transformed features.

**What is logistic regression?** It finds a weighted combination of the input features that best predicts the log-odds of default. The formula:

```
log( P(default) / P(no default) ) = intercept + w1×UrbanRural_woe + w2×naics_sector_woe + ...
```

Squash that through a sigmoid function → probability between 0 and 1.

**Why not XGBoost or neural nets?** This is a deliberate choice:
- Logistic regression with WoE is the **industry standard** for credit scorecards
- Regulators understand and accept it
- Every coefficient is interpretable: "this feature increases default odds by X%"
- It's what IDLC and other banks actually use in production

**Model results (all 5 features highly significant, p < 0.001):**
```
UrbanRural_woe   : 0.779  (urban businesses default more)
State_woe        : 0.867  (location matters)
NoEmp_woe        : 0.717  (fewer employees = riskier)
naics_sector_woe : 0.253  (industry sector matters)
RevLineCr_woe    : 0.302  (revolving credit = riskier)
```

**Output files:** `models/bins.rds` (WoE bins), `models/model.rds` (trained model)

---

## Script 4 — `R/04_evaluate.R`: Testing the Model

Now we see how well the model performs on the 9,000 rows it has **never seen**.

### Step 1 — Score the test set
Apply the same WoE transformation → predict probability of default for each of the 9,000 test loans.

### Step 2 — AUC (Area Under the ROC Curve)

**What it measures:** If you pick one random defaulter and one random non-defaulter from the test set, AUC is the probability that the model gives the defaulter a higher risk score.

- AUC = 0.5 → the model is as good as flipping a coin
- AUC = 1.0 → the model is perfect
- **Our AUC = 0.6875** → the model correctly ranks the riskier loan 69% of the time

In credit scoring, 0.70+ is considered acceptable. We're just below that threshold — reasonable given we only used 5 features and no loan history data.

### Step 3 — KS (Kolmogorov–Smirnov Statistic)

**What it measures:** The maximum separation between the cumulative score distribution of defaulters and non-defaulters. Imagine two curves — one climbing steeply for defaulters, one climbing gently for non-defaulters. KS is the biggest gap between the two curves.

- KS = 0 → the model can't separate the two groups at all
- KS = 1 → perfect separation
- **Our KS = 0.3012** — acceptable (0.20+ is considered workable in credit scoring)

The KS-optimal threshold (0.188) is the cut-off point where the two groups are furthest apart.

### Step 4 — Confusion Matrix

At threshold 0.5 (classify as default if predicted probability ≥ 50%):
```
TP=0    FP=0      ← model never predicts default at this threshold
FN=1580  TN=7419  ← all actual defaults are missed
```
This shows the model is conservative — its predicted probabilities rarely exceed 50%. At the KS-optimal threshold (0.188):
```
TP=1160  FP=3212   ← catches 73% of actual defaults
FN=420   TN=4207   ← but also flags many non-defaults as risky
```
This is a real credit-risk trade-off: catching more defaults means more false alarms.

**Output:** `models/metrics.rds` — all numbers above, saved for the dashboard.

---

## The Dashboard — `app/app.R`

The dashboard is a Shiny web app — an interactive web page built entirely in R. Run it with `shiny::runApp("app/")` and it opens in your browser.

It has **3 tabs:**

---

### Tab 1 — Portfolio

**What you see:** A high-level view of the training dataset.

**4 KPI cards** at the top:
- Total Loans: 21,000
- Overall Default Rate: 17.6%
- Avg Loan Size: $192,110
- Avg Term: 111 months

**4 interactive charts:**
- Default rate by industry sector (which sectors are riskiest?)
- Default rate by loan size (do bigger loans default more?)
- Default rate by state (which states are riskiest?)
- Default rate by year (how has default risk changed over time?)

All charts are interactive — hover over a bar to see the exact number, zoom in, etc.

---

### Tab 2 — Check Applicant

**What you see:** A loan application form.

**How it works:**
1. Fill in the 8 fields in the left sidebar (loan amount, term, industry, state, etc.)
2. Click "Check Risk"
3. The model instantly predicts the probability of default

**What you get:**
- A big percentage: the predicted default probability (e.g., "23%")
- A risk tier: Low (<10%), Medium (10–30%), High (>30%)
- A bar chart showing each feature's contribution — which inputs pushed the risk up (red bars) and which pushed it down (blue bars). This is how you explain to a customer *why* they got a certain risk rating.

**Under the hood:** Your inputs are converted to WoE scores using the same bins from training, fed into the logistic regression model, and a probability pops out. The contributions are `WoE value × model coefficient` for each feature.

---

### Tab 3 — Model Performance

**What you see:** Charts that show how good the model is, using the 9,000 test loans.

**ROC Curve:** A curve plotting True Positive Rate vs False Positive Rate at every possible threshold. The further it bulges toward the top-left corner, the better. AUC = 0.6875 is shown in the title.

**KS Plot:** Two cumulative distribution curves — one for defaulters (red), one for non-defaulters (blue). The gap between them is the KS statistic (0.3012). The wider the gap, the better the model separates the two groups.

**Histogram:** Distribution of predicted probabilities, coloured by actual outcome. Ideally, the red (default) bars cluster on the right (high risk) and blue (non-default) bars cluster on the left.

**Confusion Matrix:** An interactive table. A slider lets you change the decision threshold from 0 to 1 and see how TP, FP, FN, TN change in real time. This shows the trade-off: a stricter threshold catches fewer defaults but also produces fewer false alarms.

---

## How to Run the Project From Scratch

```powershell
# 1. Make sure R is installed (D:\R-4.6.1\bin\Rscript.exe)
# 2. Add R to PATH
$env:PATH += ";D:\R-4.6.1\bin"

# 3. Go to the project folder
cd "D:\IDLC-DATA-SCIENTIST PROJECT\sme-loan-risk"

# 4. Install packages (one-time, ~5 min)
Rscript -e "install.packages(c('dplyr','readr','lubridate','scorecard','pROC','shiny','bslib','plotly','DT','rsconnect','ggplot2','scales','tidyr'), repos='https://cloud.r-project.org')"

# 5. Run the 4 scripts in order
Rscript R/01_data_prep.R    # cleans data, ~2 min
Rscript R/02_eda.R           # builds chart data, ~10 sec
Rscript R/03_model.R         # trains model — PAUSES to show IV table, press Enter
Rscript R/04_evaluate.R      # evaluates model — PAUSES to show AUC+KS, press Enter

# 6. Launch the dashboard
Rscript -e "shiny::runApp('app/')"
```

---

## Why This Project Matters for IDLC

IDLC Finance is a credit-focused NBFI (non-bank financial institution) in Bangladesh. Their SME lending team uses credit risk models to approve or decline loan applications.

This project demonstrates:

1. **Domain knowledge** — WoE/IV and logistic regression are the industry-standard credit scorecard methodology, not just generic ML
2. **End-to-end pipeline** — from raw CSV to deployed dashboard, every step is reproducible
3. **Interpretability** — every prediction comes with an explanation (WoE contributions per feature) that a loan officer can understand and defend
4. **Real data** — 899,000 actual SBA loan outcomes, not a toy dataset
5. **Practical judgment** — dropping `Term` (IV=4.65) for suspected leakage, not just blindly keeping the highest-IV features

---

## Glossary

| Term | Plain-English meaning |
|------|-----------------------|
| Default | Borrower stopped paying the loan; bank writes it off |
| WoE | For each value of a feature, how much more (or less) likely is default compared to average |
| IV | A single number scoring how useful a feature is overall for predicting default |
| AUC | If you pick a random defaulter and a random payer, probability the model ranks the defaulter as riskier |
| KS | The biggest gap between the score distributions of defaulters and non-defaulters |
| Logistic Regression | A model that learns weights for each feature and outputs a probability between 0 and 1 |
| Train/Test Split | Divide data into a learning set (train) and a verification set (test) the model never sees during training |
| Stratified | When splitting or sampling, preserve the same ratio of defaults to non-defaults as in the original data |
| Threshold | The cut-off probability above which we classify a loan as "predicted default" |
| TP/FP/FN/TN | True Positive, False Positive, False Negative, True Negative — the 4 cells of a confusion matrix |
