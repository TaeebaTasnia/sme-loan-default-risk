# app/app.R
# Run with: shiny::runApp("app/")  from the project root.
# All charts built as native plotly — no ggplotly() conversion.

library(shiny)
library(bslib)
library(plotly)
library(dplyr)
library(scorecard)
library(tidyr)

# ── Path helper ───────────────────────────────────────────────────────────────

find_rds <- function(rel_path) {
  local_path  <- file.path("..", rel_path)
  if (file.exists(local_path))  return(local_path)
  if (file.exists(rel_path))    return(rel_path)
  stop("Cannot find: ", rel_path)
}

# ── Globals ───────────────────────────────────────────────────────────────────

eda     <- readRDS(find_rds("plots/eda_plots.rds"))
train   <- readRDS(find_rds("data/train.rds"))
bins    <- readRDS(find_rds("models/bins.rds"))
model   <- readRDS(find_rds("models/model.rds"))
metrics <- readRDS(find_rds("models/metrics.rds"))

train <- train |> mutate(default_flag = as.numeric(default_flag))
sector_levels <- levels(train$naics_sector)
state_levels  <- levels(train$State)

# ── Shared plotly layout defaults ────────────────────────────────────────────

base_layout <- list(
  font       = list(family = "Arial, sans-serif", size = 12),
  margin     = list(l = 80, r = 30, t = 40, b = 60),
  plot_bgcolor  = "white",
  paper_bgcolor = "white",
  hoverlabel = list(bgcolor = "white", font = list(size = 12))
)

apply_layout <- function(p, overrides = list()) {
  args <- modifyList(base_layout, overrides)
  do.call(layout, c(list(p), args))
}

# Colour scale: blue (low default) → red (high default)
bar_colors <- function(vals) {
  rng  <- range(vals, na.rm = TRUE)
  norm <- (vals - rng[1]) / max(rng[2] - rng[1], 1e-9)
  grDevices::colorRamp(c("#6baed6", "#cb181d"))(norm) |>
    apply(1, function(r) grDevices::rgb(r[1], r[2], r[3], maxColorValue = 255))
}

# ── UI ────────────────────────────────────────────────────────────────────────

ui <- page_navbar(
  title = "SME Loan Risk Dashboard",
  theme = bs_theme(bootswatch = "flatly"),
  lang  = "en",

  # ── Tab 1: Portfolio ────────────────────────────────────────────────────────
  nav_panel(
    "Portfolio",

    layout_columns(
      col_widths = c(3, 3, 3, 3),
      value_box("Total Loans",        format(eda$kpis$total_loans, big.mark = ","),      theme = "primary"),
      value_box("Overall Default Rate", paste0(eda$kpis$default_rate_pct, "%"),          theme = "danger"),
      value_box("Avg Loan Size",      paste0("$", format(eda$kpis$avg_loan_size, big.mark = ",")), theme = "success"),
      value_box("Avg Term",           paste0(eda$kpis$avg_term_months, " months"),       theme = "info")
    ),
    layout_columns(
      col_widths = c(6, 6),
      card(card_header("Default Rate by Industry"), plotlyOutput("p_industry", height = "320px")),
      card(card_header("Default Rate by Loan Size"), plotlyOutput("p_size",   height = "320px"))
    ),
    layout_columns(
      col_widths = c(6, 6),
      card(card_header("Default Rate by State"),   plotlyOutput("p_state",    height = "320px")),
      card(card_header("Default Rate by Year"),    plotlyOutput("p_year",     height = "320px"))
    )
  ),

  # ── Tab 2: Check Applicant ──────────────────────────────────────────────────
  nav_panel(
    "Check Applicant",
    layout_sidebar(
      sidebar = sidebar(
        width = 280,
        numericInput("loan_amount",  "Loan Amount ($)",          value = 150000, min = 1000, step = 5000),
        numericInput("term",         "Term (months)",            value = 84,     min = 1,    max = 600),
        selectInput( "naics_sector", "NAICS Sector",             choices = sector_levels),
        selectInput( "state",        "State",                    choices = state_levels),
        numericInput("no_emp",       "No. of Employees",         value = 10,     min = 0),
        selectInput( "new_exist",    "Business Type",
                     choices = c("Existing (1)" = "1", "New (2)" = "2")),
        selectInput( "urban_rural",  "Location Type",
                     choices = c("Urban (1)" = "1", "Rural (2)" = "2", "Undefined (0)" = "0")),
        selectInput( "rev_line_cr",  "Revolving Line of Credit",
                     choices = c("Yes" = "Y", "No" = "N")),
        actionButton("check_btn", "Check Risk", class = "btn-primary w-100 mt-2")
      ),
      uiOutput("applicant_result")
    )
  ),

  # ── Tab 3: Model Performance ─────────────────────────────────────────────────
  nav_panel(
    "Model Performance",
    layout_columns(
      col_widths = c(6, 6),
      card(card_header(textOutput("roc_title")), plotlyOutput("p_roc",  height = "340px")),
      card(card_header(textOutput("ks_title")),  plotlyOutput("p_ks",   height = "340px"))
    ),
    card(card_header("Predicted Probability Distribution"), plotlyOutput("p_hist", height = "280px")),
    card(
      card_header("Confusion Matrix"),
      sliderInput("threshold", "Decision Threshold", min = 0, max = 1, value = 0.5, step = 0.01, width = "50%"),
      tableOutput("conf_matrix")
    )
  )
)

# ── Server ────────────────────────────────────────────────────────────────────

server <- function(input, output, session) {

  # -- Tab 1: EDA plots (native plotly) ----------------------------------------

  output$p_industry <- renderPlotly({
    d <- eda$data_industry
    plot_ly(d, x = ~default_rate, y = ~naics_sector, type = "bar", orientation = "h",
            marker = list(color = bar_colors(d$default_rate)),
            hovertemplate = "Sector %{y}<br>Default rate: %{x:.1%}<extra></extra>") |>
      apply_layout(list(
        title  = list(text = "", x = 0),
        xaxis  = list(title = "Default Rate", tickformat = ".0%", showgrid = TRUE),
        yaxis  = list(title = "", automargin = TRUE, tickfont = list(size = 12)),
        margin = list(l = 60, r = 20, t = 10, b = 50)
      ))
  })

  output$p_size <- renderPlotly({
    d <- eda$data_size
    plot_ly(d, x = ~loan_bucket, y = ~default_rate, type = "bar",
            marker = list(color = bar_colors(d$default_rate)),
            hovertemplate = "%{x}<br>Default rate: %{y:.1%}<extra></extra>") |>
      apply_layout(list(
        xaxis  = list(title = "Loan Amount", automargin = TRUE),
        yaxis  = list(title = "Default Rate", tickformat = ".0%"),
        margin = list(l = 70, r = 20, t = 10, b = 60)
      ))
  })

  output$p_state <- renderPlotly({
    d <- eda$data_state
    plot_ly(d, x = ~default_rate, y = ~State, type = "bar", orientation = "h",
            marker = list(color = bar_colors(d$default_rate)),
            hovertemplate = "%{y}<br>Default rate: %{x:.1%}<extra></extra>") |>
      apply_layout(list(
        xaxis  = list(title = "Default Rate", tickformat = ".0%", showgrid = TRUE),
        yaxis  = list(title = "", automargin = TRUE, tickfont = list(size = 12)),
        margin = list(l = 50, r = 20, t = 10, b = 50)
      ))
  })

  output$p_year <- renderPlotly({
    d <- eda$data_year
    plot_ly(d, x = ~ApprovalYear, y = ~default_rate, type = "scatter", mode = "lines+markers",
            line    = list(color = "#2171b5", width = 2),
            marker  = list(color = "#2171b5", size = 6),
            hovertemplate = "Year: %{x}<br>Default rate: %{y:.1%}<extra></extra>") |>
      apply_layout(list(
        xaxis  = list(title = "Year"),
        yaxis  = list(title = "Default Rate", tickformat = ".0%", automargin = TRUE),
        margin = list(l = 70, r = 20, t = 10, b = 50)
      ))
  })

  # -- Tab 2: Applicant scorer -------------------------------------------------

  applicant_risk <- eventReactive(input$check_btn, {
    applicant <- data.frame(
      GrAppv       = as.numeric(input$loan_amount),
      Term         = as.numeric(input$term),
      naics_sector = factor(input$naics_sector, levels = sector_levels),
      State        = factor(input$state,        levels = state_levels),
      NoEmp        = as.numeric(input$no_emp),
      NewExist     = factor(input$new_exist,    levels = levels(train$NewExist)),
      UrbanRural   = factor(input$urban_rural,  levels = levels(train$UrbanRural)),
      RevLineCr    = factor(input$rev_line_cr,  levels = levels(train$RevLineCr)),
      default_flag = 0L,
      stringsAsFactors = FALSE
    )
    applicant_woe <- woebin_ply(applicant, bins)
    prob  <- predict(model, newdata = applicant_woe, type = "response")
    coefs <- coef(model)
    woe_cols <- grep("_woe$", names(applicant_woe), value = TRUE)
    contributions <- sapply(woe_cols, function(col) {
      if (col %in% names(coefs)) applicant_woe[[col]] * coefs[[col]] else NA_real_
    })
    list(prob = prob, contributions = contributions[!is.na(contributions)])
  })

  output$applicant_result <- renderUI({
    req(input$check_btn)
    risk <- applicant_risk()
    pct  <- round(risk$prob * 100, 1)
    tier_color <- if (pct < 10) "success" else if (pct < 30) "warning" else "danger"
    tier_label <- if (pct < 10) "Low Risk"   else if (pct < 30) "Medium Risk" else "High Risk"
    tagList(
      layout_columns(
        col_widths = c(4, 8),
        value_box(title = tier_label, value = paste0(pct, "%"), theme = tier_color),
        card(card_header("WoE Contributions (red = pushes risk up)"),
             plotlyOutput("p_contributions", height = "240px"))
      )
    )
  })

  output$p_contributions <- renderPlotly({
    req(input$check_btn)
    risk <- applicant_risk()
    d <- data.frame(
      feature      = sub("_woe$", "", names(risk$contributions)),
      contribution = as.numeric(risk$contributions)
    ) |> arrange(contribution)

    colors <- ifelse(d$contribution > 0, "#cb181d", "#2171b5")
    plot_ly(d, x = ~contribution, y = ~reorder(feature, contribution),
            type = "bar", orientation = "h",
            marker = list(color = colors),
            hovertemplate = "%{y}: %{x:.3f}<extra></extra>") |>
      apply_layout(list(
        xaxis  = list(title = "Log-odds contribution"),
        yaxis  = list(title = "", automargin = TRUE),
        margin = list(l = 100, r = 20, t = 10, b = 50)
      ))
  })

  # -- Tab 3: Model performance (native plotly) ---------------------------------

  output$roc_title <- renderText({ sprintf("ROC Curve  (AUC = %.4f)", metrics$auc) })
  output$ks_title  <- renderText({ sprintf("KS Plot  (KS = %.4f)",   metrics$ks)  })

  output$p_roc <- renderPlotly({
    fpr <- 1 - metrics$roc_obj$specificities
    tpr <- metrics$roc_obj$sensitivities
    plot_ly() |>
      add_lines(x = fpr, y = tpr, name = "ROC",
                line = list(color = "#2171b5", width = 2),
                hovertemplate = "FPR: %{x:.2f}<br>TPR: %{y:.2f}<extra></extra>") |>
      add_lines(x = c(0, 1), y = c(0, 1), name = "Random",
                line = list(color = "grey", dash = "dash", width = 1),
                hoverinfo = "skip") |>
      apply_layout(list(
        xaxis  = list(title = "False Positive Rate", range = c(0, 1)),
        yaxis  = list(title = "True Positive Rate",  range = c(0, 1), automargin = TRUE),
        legend = list(x = 0.6, y = 0.1),
        margin = list(l = 70, r = 20, t = 10, b = 60)
      ))
  })

  output$p_ks <- renderPlotly({
    d <- metrics$cdf_df
    plot_ly() |>
      add_lines(data = d, x = ~prob, y = ~cum_good, name = "Non-default",
                line = list(color = "#2171b5", width = 2),
                hovertemplate = "Prob: %{x:.2f}<br>CDF: %{y:.2f}<extra></extra>") |>
      add_lines(data = d, x = ~prob, y = ~cum_bad,  name = "Default",
                line = list(color = "#cb181d", width = 2),
                hovertemplate = "Prob: %{x:.2f}<br>CDF: %{y:.2f}<extra></extra>") |>
      apply_layout(list(
        xaxis  = list(title = "Predicted Probability"),
        yaxis  = list(title = "Cumulative Fraction", range = c(0, 1), automargin = TRUE),
        legend = list(x = 0.6, y = 0.1),
        margin = list(l = 70, r = 20, t = 10, b = 60)
      ))
  })

  output$p_hist <- renderPlotly({
    non_def <- metrics$pred_prob[metrics$actual == 0]
    def     <- metrics$pred_prob[metrics$actual == 1]
    plot_ly() |>
      add_histogram(x = non_def, name = "Non-default", nbinsx = 40,
                    marker = list(color = "rgba(33,113,181,0.7)")) |>
      add_histogram(x = def,     name = "Default",     nbinsx = 40,
                    marker = list(color = "rgba(203,24,29,0.7)")) |>
      layout(barmode = "overlay") |>
      apply_layout(list(
        xaxis  = list(title = "Predicted Probability"),
        yaxis  = list(title = "Count", automargin = TRUE),
        legend = list(x = 0.75, y = 0.9),
        margin = list(l = 70, r = 20, t = 10, b = 60)
      ))
  })

  output$conf_matrix <- renderTable({
    thresh     <- input$threshold
    pred_class <- as.integer(metrics$pred_prob >= thresh)
    actual     <- metrics$actual
    tp <- sum(actual == 1 & pred_class == 1)
    fp <- sum(actual == 0 & pred_class == 1)
    fn <- sum(actual == 1 & pred_class == 0)
    tn <- sum(actual == 0 & pred_class == 0)
    data.frame(
      ` `                  = c("Predicted Default", "Predicted Non-default"),
      `Actual Default`     = c(tp, fn),
      `Actual Non-default` = c(fp, tn),
      check.names = FALSE
    )
  }, striped = TRUE, bordered = TRUE, align = "c")
}

shinyApp(ui, server)
