# R/02_eda.R
# Saves aggregated data frames + KPIs to plots/eda_plots.rds.
# The app builds native plotly charts from these data frames — no ggplot conversion.

library(dplyr)

train <- readRDS("data/train.rds")

default_rate <- function(df, group_var) {
  df |>
    group_by({{ group_var }}) |>
    summarise(n = n(), default_rate = mean(default_flag), .groups = "drop")
}

# ── Data for each chart ───────────────────────────────────────────────────────

top_sectors <- train |> count(naics_sector, sort = TRUE) |> slice_head(n = 10) |> pull(naics_sector)
data_industry <- train |>
  filter(naics_sector %in% top_sectors) |>
  default_rate(naics_sector) |>
  arrange(default_rate) |>
  mutate(naics_sector = as.character(naics_sector))

data_size <- train |>
  mutate(loan_bucket = cut(GrAppv,
    breaks = c(0, 50000, 150000, 500000, Inf),
    labels = c("$0-50k", "$50-150k", "$150-500k", "$500k+"), right = TRUE)) |>
  default_rate(loan_bucket) |>
  mutate(loan_bucket = as.character(loan_bucket))

top_states <- train |> count(State, sort = TRUE) |> slice_head(n = 10) |> pull(State)
data_state <- train |>
  filter(State %in% top_states) |>
  default_rate(State) |>
  arrange(default_rate) |>
  mutate(State = as.character(State))

data_year <- train |>
  default_rate(ApprovalYear) |>
  filter(!is.na(ApprovalYear)) |>
  arrange(ApprovalYear)

# ── KPIs ──────────────────────────────────────────────────────────────────────

kpis <- list(
  total_loans      = nrow(train),
  default_rate_pct = round(mean(train$default_flag) * 100, 1),
  avg_loan_size    = round(mean(train$GrAppv, na.rm = TRUE)),
  avg_term_months  = round(mean(train$Term, na.rm = TRUE))
)

message("KPIs: ", kpis$total_loans, " loans | ",
        kpis$default_rate_pct, "% default | $",
        format(kpis$avg_loan_size, big.mark = ","), " avg | ",
        kpis$avg_term_months, " months avg term")

saveRDS(list(
  data_industry = data_industry,
  data_size     = data_size,
  data_state    = data_state,
  data_year     = data_year,
  kpis          = kpis
), "plots/eda_plots.rds")

message("Saved plots/eda_plots.rds")
