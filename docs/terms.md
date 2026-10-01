# Key Terms — SME Loan Risk Model

Interview prep notes. Plain English, no formulas unless strictly needed.

---

## Weight of Evidence (WoE)

WoE measures how strongly a particular bin of a feature separates defaulters from non-defaulters. For each bin, it is the log of the ratio of the share of defaults in that bin to the share of non-defaults: a positive WoE means the bin contains more defaulters than average, and a negative WoE means fewer. Turning every feature into WoE scores before fitting a logistic regression is the standard credit-industry pre-processing step because it converts mixed data types (numbers, categories) onto a common numeric scale aligned with log-odds.

---

## Information Value (IV)

IV summarises how useful a single feature is across all its bins combined — it is the sum of WoE differences weighted by the population share of each bin. The rule of thumb used in credit scoring is: IV below 0.02 means the feature has no useful signal, 0.02–0.1 is weak, 0.1–0.3 is medium, 0.3–0.5 is strong, and above 0.5 is suspiciously perfect (which usually signals data leakage rather than genuine predictive power). In this project, the IV filter removes features outside the 0.02–0.5 range before fitting the model.

---

## AUC (Area Under the ROC Curve)

AUC is the probability that the model assigns a higher risk score to a randomly chosen defaulter than to a randomly chosen non-defaulter — it measures ranking ability, not a specific cut-off. A value of 0.5 means the model is no better than a coin flip; a value of 1.0 means it separates defaulters and non-defaulters perfectly. In practice, a consumer or SME credit model with AUC above 0.70 is considered usable, and above 0.80 is considered strong.

---

## KS (Kolmogorov–Smirnov Statistic)

KS is the maximum vertical distance between the cumulative distribution of predicted scores for defaulters and the cumulative distribution for non-defaulters. Intuitively, it answers: "at the single best cut-off, how far apart are the two groups?" A KS of 0 means the distributions completely overlap; a KS of 1 means they are completely separated. In credit scoring, a KS above 0.20 is acceptable and above 0.40 is strong. The KS-optimal threshold (the cut-off that maximises this distance) is one of the two thresholds evaluated in the confusion matrix.
