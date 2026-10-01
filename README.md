# SME Loan Default Risk Model

An end-to-end credit risk model built in R, using real US Small Business Administration (SBA) loan data to predict which SME loans will default. The project demonstrates the standard credit-scoring workflow — Weight of Evidence feature engineering, Information Value filtering, and logistic regression — and packages the results in a three-tab Shiny dashboard deployed to shinyapps.io. It was built as a portfolio project for a Data Scientist (Credit-SME) role at IDLC Finance and serves as the R counterpart to the Python XGBoost ChurnGuard classifier.

---

## Dataset

**Source:** Kaggle — [Should This Loan Be Approved or Denied?](https://www.kaggle.com/datasets/mirbektoktogaraev/should-this-loan-be-approved-or-denied) by Mirbek Toktogaraev.  
**File:** `SBAnational.csv` · ~170 MB · ~899 k rows of real US SBA loans.  
**Target:** `MIS_Status` — `P I F` (paid in full) or `CHGOFF` (charged-off / defaulted).  
**Citation:** Li, Amy, Mickel, and Taylor. "Should This Loan Be Approved or Denied?: A Large Dataset with Class Assignment Guidelines." *Journal of Statistics Education* 26, no. 1 (2018): 55–66.

---

## Key Terms

**WoE (Weight of Evidence):** For each bin of a feature, the log of the ratio of the default share to the non-default share — converts every feature onto a common log-odds scale, the standard credit-industry pre-processing step.

**IV (Information Value):** A single number per feature that sums up how well its WoE bins separate defaulters from non-defaulters; features with IV below 0.02 (no signal) or above 0.5 (likely leakage) are dropped.

**AUC (Area Under the ROC Curve):** The probability that the model ranks a random defaulter higher than a random non-defaulter; 0.5 = random, 1.0 = perfect.

**KS (Kolmogorov–Smirnov):** The maximum separation between the cumulative score distributions of defaulters and non-defaulters; the cut-off that achieves this maximum is the KS-optimal decision threshold.

---

## Model Performance

| Metric | Value |
|--------|-------|
| AUC    | 0.6875 |
| KS     | 0.3012 (at threshold 0.188) |

---

## How to Run Locally

```r
# 1. Install dependencies
install.packages(c(
  "dplyr", "readr", "lubridate", "scorecard", "pROC",
  "shiny", "bslib", "bsicons", "plotly", "DT",
  "rsconnect", "ggplot2", "scales", "tidyr"
))

# 2. Place SBAnational.csv one directory above sme-loan-risk/
#    (i.e., as a sibling of the project folder, not inside it)

# 3. Open sme-loan-risk.Rproj in RStudio, then run in order:
source("R/01_data_prep.R")   # ~2 min — produces data/*.rds
source("R/02_eda.R")          # <1 min — produces plots/eda_plots.rds
source("R/03_model.R")        # ~2 min — PAUSES to show IV table
source("R/04_evaluate.R")     # <1 min — PAUSES to show AUC + KS

# 4. Launch the dashboard
shiny::runApp("app/")
```

---

## Deploy to shinyapps.io

```r
# 1. Create a free account at https://www.shinyapps.io
# 2. Copy your token from Account → Tokens
rsconnect::setAccountInfo(
  name   = "<your-shinyapps-username>",
  token  = "<your-token>",
  secret = "<your-secret>"
)

# 3. Bundle the .rds files into app/ so they are uploaded with the app
#    (shinyapps.io only sees files inside the deployed directory)
dir.create("app/data",   showWarnings = FALSE)
dir.create("app/models", showWarnings = FALSE)
dir.create("app/plots",  showWarnings = FALSE)
file.copy(list.files("data",   full.names = TRUE, pattern = "\\.rds$"), "app/data/")
file.copy(list.files("models", full.names = TRUE, pattern = "\\.rds$"), "app/models/")
file.copy(list.files("plots",  full.names = TRUE, pattern = "\\.rds$"), "app/plots/")

# 4. Deploy
rsconnect::deployApp("app/", appName = "sme-loan-risk")
```

**Deployed URL:** [fill after deploy]
