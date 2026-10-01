# R/04_evaluate.R
# Scores the test set, computes AUC + KS + confusion matrices.
# PAUSES to show you AUC and KS before writing metrics.rds.
# Source after 03_model.R: source("R/04_evaluate.R")

library(dplyr)
library(pROC)
library(scorecard)

test  <- readRDS("data/test.rds")
bins  <- readRDS("models/bins.rds")
model <- readRDS("models/model.rds")

# ── 1. Prepare test set ───────────────────────────────────────────────────────

test <- test |> mutate(default_flag = as.numeric(default_flag))

# Keep only the features the model was trained on (bins keys tell us which ones).
model_features <- names(bins)
test_keep <- test |> select(all_of(c(model_features, "default_flag")))

# WoE-transform test with the SAME bins fitted on train — no leakage.
test_woe <- woebin_ply(test_keep, bins)
test_woe <- test_woe |> mutate(default_flag = as.numeric(default_flag))

# ── 2. Predict ───────────────────────────────────────────────────────────────

pred_prob <- predict(model, newdata = test_woe, type = "response")
actual    <- test_woe$default_flag

# ── 3. AUC ───────────────────────────────────────────────────────────────────
#
# AUC (Area Under the ROC Curve) = P(model scores a random defaulter higher
# than a random non-defaulter). 0.5 = random; 1.0 = perfect.

roc_obj <- roc(actual, pred_prob, quiet = TRUE)
auc_val <- as.numeric(auc(roc_obj))

# ── 4. KS statistic ──────────────────────────────────────────────────────────
#
# Kolmogorov–Smirnov: maximum vertical gap between the cumulative distribution
# of defaulter scores and non-defaulter scores.
# Computed directly from the pROC roc object to avoid relying on undocumented
# internals of scorecard::perf_eva (whose return structure varies by version).
#
# At each threshold t: gap = sensitivity(t) + specificity(t) - 1
# = TPR(t) - FPR(t) = |CDF_defaulters(t) - CDF_non-defaulters(t)|
# KS = max of that gap across all thresholds.

ks_gaps      <- abs(roc_obj$sensitivities + roc_obj$specificities - 1)
ks_idx       <- which.max(ks_gaps)
ks_val       <- ks_gaps[ks_idx]
ks_threshold <- roc_obj$thresholds[ks_idx]

# KS CDF data for the app's KS plot.
# Sorts predictions ascending and accumulates the fraction of non-defaults
# (cum_good) and defaults (cum_bad) captured up to each cut-off.
cdf_df <- data.frame(prob = pred_prob, actual = actual) |>
  arrange(prob) |>
  mutate(
    cum_good = cumsum(actual == 0) / sum(actual == 0),
    cum_bad  = cumsum(actual == 1) / sum(actual == 1)
  )

# ── 5. Confusion matrix helper ───────────────────────────────────────────────

confusion_at_threshold <- function(actual, pred_prob, threshold) {
  pred_class <- as.integer(pred_prob >= threshold)
  tp <- sum(actual == 1 & pred_class == 1)
  fp <- sum(actual == 0 & pred_class == 1)
  fn <- sum(actual == 1 & pred_class == 0)
  tn <- sum(actual == 0 & pred_class == 0)
  list(TP = tp, FP = fp, FN = fn, TN = tn,
       precision  = if ((tp + fp) > 0) tp / (tp + fp) else NA_real_,
       recall     = if ((tp + fn) > 0) tp / (tp + fn) else NA_real_,
       threshold  = threshold)
}

cm_05 <- confusion_at_threshold(actual, pred_prob, 0.5)
cm_ks <- confusion_at_threshold(actual, pred_prob, ks_threshold)

# ── 6. PAUSE — review before writing ─────────────────────────────────────────

message("\n========================================")
message(sprintf("  AUC : %.4f", auc_val))
message(sprintf("  KS  : %.4f  (at threshold %.3f)", ks_val, ks_threshold))
message("----------------------------------------")
message("  Confusion matrix at threshold 0.50:")
message(sprintf("    TP=%d  FP=%d  FN=%d  TN=%d", cm_05$TP, cm_05$FP, cm_05$FN, cm_05$TN))
message("  Confusion matrix at KS-optimal threshold:")
message(sprintf("    TP=%d  FP=%d  FN=%d  TN=%d", cm_ks$TP, cm_ks$FP, cm_ks$FN, cm_ks$TN))
message("========================================\n")

readline(">>> Copy the AUC and KS into README.md, then press Enter to save metrics.rds...")

# ── 7. Save ───────────────────────────────────────────────────────────────────

metrics <- list(
  auc          = auc_val,
  ks           = ks_val,
  ks_threshold = ks_threshold,
  cm_05        = cm_05,
  cm_ks        = cm_ks,
  roc_obj      = roc_obj,   # pROC object — used by app for the ROC plot
  cdf_df       = cdf_df,    # pre-computed CDF curves — used by app for KS plot
  pred_prob    = pred_prob,
  actual       = actual
)

saveRDS(metrics, "models/metrics.rds")
message("Saved models/metrics.rds — open app/app.R and run shiny::runApp('app/').")
