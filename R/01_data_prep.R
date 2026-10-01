# R/01_data_prep.R
# Run once to produce data/train.rds and data/test.rds.
# Source from the project root: source("R/01_data_prep.R")

library(dplyr)
library(readr)
library(lubridate)

set.seed(42)

# ── 1. Read raw CSV ──────────────────────────────────────────────────────────

# CSV lives one level above the project root to avoid duplicating 179 MB.
csv_path <- "../SBAnational.csv"

if (!file.exists(csv_path)) {
  stop(
    "SBAnational.csv not found at ", normalizePath(csv_path, mustWork = FALSE),
    "\nDownload it from: https://www.kaggle.com/datasets/mirbektoktogaraev/should-this-loan-be-approved-or-denied",
    "\nThen place it one directory above sme-loan-risk/ (alongside this project folder)."
  )
}

message("Reading CSV — this takes ~30 s for 899 k rows...")

raw <- read_csv(
  csv_path,
  col_types = cols(
    LoanNr_ChkDgt  = col_character(),
    Name           = col_character(),
    City           = col_character(),
    State          = col_character(),
    Zip            = col_character(),
    Bank           = col_character(),
    BankState      = col_character(),
    NAICS          = col_character(),
    ApprovalDate   = col_character(),
    ApprovalFY     = col_character(),
    Term           = col_double(),
    NoEmp          = col_double(),
    NewExist       = col_character(),
    CreateJob      = col_double(),
    RetainedJob    = col_double(),
    FranchiseCode  = col_character(),
    UrbanRural     = col_character(),
    RevLineCr      = col_character(),
    LowDoc         = col_character(),
    ChgOffDate     = col_character(),
    DisbursementDate = col_character(),
    DisbursementGross = col_character(),
    BalanceGross   = col_character(),
    MIS_Status     = col_character(),
    ChgOffPrinGr   = col_character(),
    GrAppv         = col_character(),
    SBA_Appv       = col_character()
  ),
  show_col_types = FALSE
)

message("Read ", nrow(raw), " rows.")

# ── 2. Parse & clean currency columns ────────────────────────────────────────

# Dollar amounts arrive as "$1,234.00" — strip symbols before converting.
strip_dollar <- function(x) as.numeric(gsub("[$,]", "", x))

raw <- raw |>
  mutate(
    GrAppv            = strip_dollar(GrAppv),
    DisbursementGross = strip_dollar(DisbursementGross),
    SBA_Appv          = strip_dollar(SBA_Appv),
    # SBA dates come as "2-Jan-96" or "02-JAN-1962" — try multiple formats
    ApprovalDate      = parse_date_time(ApprovalDate,
                                        orders = c("d-b-y", "d-b-Y", "mdy", "dmy"),
                                        quiet  = TRUE),
    ApprovalYear      = year(ApprovalDate)
  )

# ── 3. Filter to labelled rows only ─────────────────────────────────────────

# Rows with any other MIS_Status value (e.g. blank) are unlabelled — drop them.
labelled <- raw |>
  filter(MIS_Status %in% c("P I F", "CHGOFF"))

message("Labelled rows (PIF + CHGOFF): ", nrow(labelled))

# ── 4. Create target + engineered features ───────────────────────────────────

labelled <- labelled |>
  mutate(
    default_flag  = if_else(MIS_Status == "CHGOFF", 1L, 0L),
    # First 2 digits of NAICS = broad industry sector (e.g. "72" = Hospitality)
    naics_sector  = factor(substr(NAICS, 1, 2)),
    State         = factor(State),
    NewExist      = factor(NewExist),
    UrbanRural    = factor(UrbanRural),
    RevLineCr     = factor(RevLineCr)
  )

# ── 5. Select the 8 model features + target + date ───────────────────────────

model_cols <- c(
  "GrAppv", "Term", "naics_sector", "State",
  "NoEmp", "NewExist", "UrbanRural", "RevLineCr",
  "default_flag", "ApprovalYear"
)

clean <- labelled |>
  select(all_of(model_cols)) |>
  filter(!is.na(GrAppv), !is.na(Term), !is.na(NoEmp))

message("Clean rows after NA drop: ", nrow(clean))

# ── 6. Stratified 30 k sample ────────────────────────────────────────────────

# Preserve the natural default rate (~17 %) so the sample isn't biased.
n_target <- 30000
n_total  <- nrow(clean)

# Use prop so n() is never called outside a data-masking context.
# prop = n_target/n_total draws the same fraction from each stratum,
# preserving the natural default rate.
sampled <- clean |>
  group_by(default_flag) |>
  slice_sample(prop = n_target / n_total) |>
  ungroup()

message("Sample size: ", nrow(sampled),
        " | Default rate: ", round(mean(sampled$default_flag) * 100, 1), "%")

saveRDS(sampled, "data/sba_sample_30k.rds")

# ── 7. Stratified 70 / 30 train-test split ───────────────────────────────────

# Split within each stratum so both sets have the same default rate.
split_data <- sampled |>
  group_by(default_flag) |>
  mutate(fold = sample(c(rep("train", ceiling(0.7 * n())),
                         rep("test",  floor(0.3 * n())))[seq_len(n())],
                       size = n(), replace = FALSE)) |>
  ungroup()

train <- split_data |> filter(fold == "train") |> select(-fold)
test  <- split_data |> filter(fold == "test")  |> select(-fold)

message("Train: ", nrow(train), " rows | Test: ", nrow(test), " rows")
message("Train default rate: ", round(mean(train$default_flag) * 100, 1), "%")
message("Test  default rate: ", round(mean(test$default_flag)  * 100, 1), "%")

saveRDS(train, "data/train.rds")
saveRDS(test,  "data/test.rds")

message("Saved data/train.rds and data/test.rds — run 02_eda.R next.")
