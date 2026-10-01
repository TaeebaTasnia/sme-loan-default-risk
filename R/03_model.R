# R/03_model.R
# WoE binning → IV filter → logistic regression.
# PAUSES before dropping features so you can review the IV table.
# Source after 02_eda.R: source("R/03_model.R")

library(dplyr)
library(scorecard)

train <- readRDS("data/train.rds")

# scorecard expects the target as character or numeric 0/1; make sure it is numeric.
train <- train |> mutate(default_flag = as.numeric(default_flag))

# Drop ApprovalYear — it's a date proxy kept for EDA only, not a loan feature.
train <- train |> select(-ApprovalYear)

# ── 1. WoE binning ───────────────────────────────────────────────────────────
#
# Weight of Evidence: for each bin of a feature,
#   WoE = log( P(event in bin) / P(non-event in bin) )
# This converts every feature — numeric or categorical — into a single numeric
# scale aligned with log-odds of default. Standard credit-industry pre-processing.

message("Running WoE binning on all features (may take ~60 s)...")

bins_all <- woebin(
  dt             = train,
  y              = "default_flag",
  positive       = "1",          # 1 = CHGOFF (defaulted) is the "positive" / event class
  check_cate_num = FALSE          # State has 50+ levels — suppress the interactive prompt
)

# ── 2. Information Value table ───────────────────────────────────────────────
#
# IV measures how much a single feature separates defaulters from non-defaulters.
# Rule of thumb used in credit scoring:
#   IV < 0.02  → useless (no predictive signal)
#   0.02–0.1   → weak
#   0.1–0.3    → medium
#   0.3–0.5    → strong
#   IV > 0.5   → suspiciously perfect (possible data leakage — drop it)

iv_table <- iv(train, y = "default_flag") |>
  arrange(desc(info_value))

message("\n=== Information Value Table ===")
print(iv_table)
message("================================\n")

# PAUSE — review before any feature is dropped.
readline(">>> Review the IV table above, then press Enter to continue with the IV filter...")

# ── 3. IV filter ─────────────────────────────────────────────────────────────

keep_vars <- iv_table |>
  filter(info_value >= 0.02, info_value <= 0.5) |>
  pull(variable)

dropped <- setdiff(iv_table$variable, keep_vars)
if (length(dropped) > 0) {
  message("Dropping features outside IV [0.02, 0.5]: ", paste(dropped, collapse = ", "))
} else {
  message("All features passed the IV filter.")
}

# Re-bin using only the surviving features so bins object is self-consistent.
train_keep <- train |> select(all_of(c(keep_vars, "default_flag")))
bins <- woebin(train_keep, y = "default_flag", positive = "1", check_cate_num = FALSE)

# ── 4. WoE transformation ────────────────────────────────────────────────────
#
# Replace each feature value with its bin's WoE score.
# The resulting data frame has one numeric column per feature — logistic
# regression can then treat them all symmetrically.

train_woe <- woebin_ply(train_keep, bins)
train_woe <- train_woe |> mutate(default_flag = as.numeric(default_flag))

# ── 5. Logistic regression ───────────────────────────────────────────────────
#
# Logistic regression on WoE-transformed features is the industry standard for
# scorecard models: interpretable coefficients, well-understood by regulators,
# and fast to fit on tens of thousands of rows.

message("Fitting logistic regression...")

model <- glm(
  default_flag ~ .,
  data   = train_woe,
  family = binomial(link = "logit")
)

message("\nModel summary:")
print(summary(model))

# ── 6. Save ──────────────────────────────────────────────────────────────────

saveRDS(bins,  "models/bins.rds")
saveRDS(model, "models/model.rds")

message("\nSaved models/bins.rds and models/model.rds — run 04_evaluate.R next.")
