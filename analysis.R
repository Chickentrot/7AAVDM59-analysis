# ============================================================
#  7AAVDM59 Data Collection and Analysis
#  Social Media Travel Content & Beach Destination Intention
#  KCL MSc Digital Economy
# ============================================================

# ── Section 1: Setup ─────────────────────────────────────────
required_packages <- c("tidyverse", "psych", "corrplot", "here")
new_packages <- required_packages[!(required_packages %in% installed.packages()[,"Package"])]
if (length(new_packages)) install.packages(new_packages, repos = "https://cran.rstudio.com/")

library(tidyverse)
library(psych)
library(corrplot)
library(here)

dir.create(here("outputs"), showWarnings = FALSE)

df <- read_csv(here("data", "data.csv"), show_col_types = FALSE)
cat("Data loaded:", nrow(df), "rows,", ncol(df), "columns\n\n")


# ── Section 2: Reverse Scoring ───────────────────────────────
# Five items are negatively worded in the BFI-2 short form:
#   Q11 — "has few artistic interests"          → low raw = high Openness
#   Q13 — "is reserved"                         → low raw = high Extraversion
#   Q15 — "starts arguments with others"        → low raw = high Agreeableness
#   Q17 — "tends to be lazy"                    → low raw = high Conscientiousness
#   Q19 — "is relaxed, handles stress well"     → low raw = high Neuroticism
# Reversing with (6 - score) so all items point in the same direction as the trait.
df <- df %>%
  mutate(
    Q11_r = 6 - Q11,
    Q13_r = 6 - Q13,
    Q15_r = 6 - Q15,
    Q17_r = 6 - Q17,
    Q19_r = 6 - Q19
  )
cat("Reverse scoring applied: Q11_r, Q13_r, Q15_r, Q17_r, Q19_r = 6 - raw\n\n")


# ── Section 3: Composite Scores ──────────────────────────────
# NA threshold: if a respondent has NA on MORE than 1 item in a composite,
# their composite score is set to NA rather than imputed from partial items.
safe_rowmeans <- function(df_sub, label, max_na = 1) {
  na_count <- rowSums(is.na(df_sub))
  result   <- rowMeans(df_sub, na.rm = TRUE)
  bad      <- na_count > max_na
  if (any(bad)) {
    warning(sprintf("%d row(s) in %s exceeded %d NA threshold — set to NA.",
                    sum(bad), label, max_na))
    cat(sprintf("  WARNING: %d row(s) in %-20s had >%d missing items → composite = NA\n",
                sum(bad), label, max_na))
    result[bad] <- NA_real_
  }
  result
}

df <- df %>%
  mutate(
    SMuse             = safe_rowmeans(pick(Q1, Q2, Q3, Q4),         "SMuse"),
    TravelIntent      = safe_rowmeans(pick(Q5, Q6, Q7, Q8, Q9),     "TravelIntent"),
    Openness          = safe_rowmeans(pick(Q10, Q11_r),              "Openness"),
    Extraversion      = safe_rowmeans(pick(Q12, Q13_r),              "Extraversion"),
    Agreeableness     = safe_rowmeans(pick(Q14, Q15_r),              "Agreeableness"),
    Conscientiousness = safe_rowmeans(pick(Q16, Q17_r),              "Conscientiousness"),
    Neuroticism       = safe_rowmeans(pick(Q18, Q19_r),              "Neuroticism")
  )

composites <- c("SMuse", "TravelIntent", "Openness", "Extraversion",
                "Agreeableness", "Conscientiousness", "Neuroticism")

cat("Composites created:\n")
cat("  SMuse             — Q1, Q2, Q3, Q4\n")
cat("  TravelIntent      — Q5, Q6, Q7, Q8, Q9\n")
cat("  Openness          — Q10, Q11_r\n")
cat("  Extraversion      — Q12, Q13_r\n")
cat("  Agreeableness     — Q14, Q15_r\n")
cat("  Conscientiousness — Q16, Q17_r\n")
cat("  Neuroticism       — Q18, Q19_r\n\n")


# ── Section 4: Descriptive Statistics ────────────────────────
desc_stats <- df %>%
  select(all_of(composites)) %>%
  pivot_longer(everything(), names_to = "Variable", values_to = "Value") %>%
  group_by(Variable) %>%
  summarise(
    n    = sum(!is.na(Value)),
    Mean = round(mean(Value, na.rm = TRUE), 2),
    SD   = round(sd(Value,   na.rm = TRUE), 2),
    Min  = round(min(Value,  na.rm = TRUE), 2),
    Max  = round(max(Value,  na.rm = TRUE), 2),
    .groups = "drop"
  ) %>%
  arrange(match(Variable, composites))

cat("── Descriptive Statistics ──────────────────────────────\n")
print(as.data.frame(desc_stats), row.names = FALSE)
cat("\n")

write_csv(desc_stats, here("outputs", "descriptives.csv"))
cat("Descriptives exported to outputs/descriptives.csv\n\n")


# ── Section 5: Shapiro-Wilk (descriptive only) ───────────────
# Shapiro-Wilk results are reported here for transparency but do NOT
# determine the correlation method. All six hypothesis tests use
# Spearman's rho (see Section 6 for justification).
cat("── Shapiro-Wilk Normality Tests (descriptive only) ─────\n")
cat("   Note: method selection is NOT based on these results.\n\n")

for (var in composites) {
  x    <- na.omit(df[[var]])
  test <- shapiro.test(x)
  cat(sprintf("  %-20s W = %.4f, p = %.4f\n", var, test$statistic, test$p.value))
}
cat("\n")


# ── Section 6: Correlation Tests (Spearman throughout) ───────
# All six hypotheses are tested with Spearman's rho. Justification:
#   (1) All composites are means of ordinal Likert items — the resulting
#       scale is at best interval-like, and parametric assumptions are not
#       guaranteed even when Shapiro-Wilk does not reject normality.
#   (2) Spearman is the standard recommendation for Likert-derived
#       composites in social-science research (Field, 2018).
#   (3) Using a single consistent method avoids post-hoc method-switching
#       that can inflate Type I error.
# Note: 95% CIs for Spearman's rho require bootstrapping and are not
# reported here. Bootstrap CIs can be added via the boot package if needed.
#
# Multiple comparisons: six simultaneous tests are conducted (H1–H6).
# Holm's sequential Bonferroni correction is applied to control the
# family-wise error rate. Both raw and Holm-adjusted p-values are reported.

# Hypothesis metadata — direction label used in output and CSV
hyp_pairs <- list(
  list(x = "SMuse",             label = "H1 (SMuse → TravelIntent)",
       direction = "Directional (positive)"),
  list(x = "Openness",          label = "H2 (Openness → TravelIntent)",
       direction = "Directional (positive)"),
  list(x = "Extraversion",      label = "H3 (Extraversion → TravelIntent)",
       direction = "Directional (positive)"),
  list(x = "Agreeableness",     label = "H4 (Agreeableness → TravelIntent)",
       direction = "Exploratory (two-tailed, no directional prediction)"),
  list(x = "Conscientiousness", label = "H5 (Conscientiousness → TravelIntent)",
       direction = "Exploratory (two-tailed, no directional prediction)"),
  list(x = "Neuroticism",       label = "H6 (Neuroticism → TravelIntent)",
       direction = "Exploratory (two-tailed, no directional prediction)")
)

# Run all six tests
test_results <- list()
for (hp in hyp_pairs) {
  test_results[[hp$x]] <- cor.test(df[[hp$x]], df$TravelIntent,
                                   method = "spearman", exact = FALSE)
}

# Apply Holm correction across all six raw p-values
p_raw  <- sapply(hyp_pairs, function(hp) test_results[[hp$x]]$p.value)
p_holm <- p.adjust(p_raw, method = "holm")

cat("── Hypothesis Tests (Spearman's rho, Holm-corrected) ───\n")
cat("   Six simultaneous tests — Holm correction applied.\n")
cat("   H1–H3: directional (positive association predicted).\n")
cat("   H4–H6: exploratory (two-tailed, no directional prediction).\n\n")

# APA format helper — Spearman only, no CI reported
r_fmt <- function(v) {
  ifelse(v >= 0,
         paste0( ".", sprintf("%02d", abs(round(v * 100)))),
         paste0("-.", sprintf("%02d", abs(round(v * 100)))))
}

p_fmt <- function(p) {
  if      (p < .001) "< .001"
  else if (p >= .9995) "= 1.000"
  else sprintf("= .%03d", round(p * 1000))
}

result_rows <- list()

for (i in seq_along(hyp_pairs)) {
  hp     <- hyp_pairs[[i]]
  t      <- test_results[[hp$x]]
  r      <- as.numeric(t$estimate)
  p_r    <- p_raw[i]
  p_h    <- p_holm[i]

  sig_raw  <- ifelse(p_r < .05, "SIGNIFICANT", "non-significant")
  sig_holm <- ifelse(p_h < .05, "SIGNIFICANT after Holm", "non-significant after Holm")

  apa <- sprintf("r_s = %s, p_raw %s, p_Holm %s",
                 r_fmt(r), p_fmt(p_r), p_fmt(p_h))

  cat(sprintf("  %s\n    %s\n    [%s | %s]\n    Direction: %s\n\n",
              hp$label, apa, sig_raw, sig_holm, hp$direction))

  result_rows[[i]] <- data.frame(
    Hypothesis          = hp$label,
    Method              = "SPEARMAN",
    r                   = round(r, 3),
    p_raw               = round(p_r, 4),
    p_holm              = round(p_h, 4),
    Significant_raw     = p_r < .05,
    Significant_holm    = p_h < .05,
    Direction_predicted = hp$direction,
    stringsAsFactors    = FALSE
  )
}

results_table <- bind_rows(result_rows)
write_csv(results_table, here("outputs", "hypothesis_results.csv"))
cat("Results exported to outputs/hypothesis_results.csv\n\n")


# ── Section 7: Visualisations ────────────────────────────────

# 7a — Correlation matrix heatmap (all 7 composites)
cor_mat <- cor(df[, composites], use = "complete.obs", method = "spearman")

png(here("outputs", "correlation_matrix.png"), width = 820, height = 720, res = 110)
corrplot(cor_mat,
         method      = "color",
         type        = "upper",
         addCoef.col = "black",
         number.cex  = 0.75,
         tl.col      = "black",
         tl.srt      = 45,
         col         = colorRampPalette(c("#4575b4", "white", "#d73027"))(200),
         title       = "Spearman Correlation Matrix — Composite Scales",
         mar         = c(0, 0, 2, 0))
dev.off()
cat("Saved: outputs/correlation_matrix.png\n")

# Shared minimal theme
theme_study <- theme_minimal(base_size = 12) +
  theme(
    plot.title       = element_text(face = "bold", size = 13, hjust = 0.5),
    axis.title       = element_text(size = 11),
    panel.grid.minor = element_blank()
  )

# Scatterplot helper — shows r_s and both p-values
scatter_plot <- function(data, x_var, y_var, x_lab, y_lab, title, r_val, p_r, p_h) {
  p_r_str <- ifelse(p_r < .001, "< .001", sprintf("= %.3f", p_r))
  p_h_str <- ifelse(p_h < .001, "< .001", sprintf("= %.3f", p_h))
  label   <- sprintf("r_s = %.2f\np_raw %s  p_Holm %s", r_val, p_r_str, p_h_str)

  ggplot(data, aes(x = .data[[x_var]], y = .data[[y_var]])) +
    geom_jitter(alpha = 0.45, width = 0.08, height = 0.08,
                colour = "#2c7bb6", size = 1.8) +
    geom_smooth(method = "lm", se = TRUE, colour = "#d73027",
                fill = "#f4a582", linewidth = 0.9) +
    annotate("text", x = Inf, y = -Inf, label = label,
             hjust = 1.05, vjust = -0.4, size = 3.4, colour = "grey30",
             lineheight = 1.3) +
    labs(title = title, x = x_lab, y = y_lab) +
    scale_x_continuous(breaks = 1:5) +
    scale_y_continuous(breaks = 1:5) +
    coord_cartesian(xlim = c(0.7, 5.3), ylim = c(0.7, 5.3)) +
    theme_study
}

scatter_specs <- list(
  list(x = "SMuse",             x_lab = "Social Media Use (SMuse)",
       title = "H1: Social Media Use and Travel Intention",      file = "H1_scatterplot.png"),
  list(x = "Openness",          x_lab = "Openness to Experience",
       title = "H2: Openness and Travel Intention",              file = "H2_scatterplot.png"),
  list(x = "Extraversion",      x_lab = "Extraversion",
       title = "H3: Extraversion and Travel Intention",          file = "H3_scatterplot.png"),
  list(x = "Agreeableness",     x_lab = "Agreeableness",
       title = "H4: Agreeableness and Travel Intention",         file = "H4_scatterplot.png"),
  list(x = "Conscientiousness", x_lab = "Conscientiousness",
       title = "H5: Conscientiousness and Travel Intention",     file = "H5_scatterplot.png"),
  list(x = "Neuroticism",       x_lab = "Neuroticism",
       title = "H6: Neuroticism and Travel Intention",           file = "H6_scatterplot.png")
)

for (i in seq_along(scatter_specs)) {
  sp   <- scatter_specs[[i]]
  t    <- test_results[[sp$x]]
  p    <- scatter_plot(df, sp$x, "TravelIntent",
                       sp$x_lab, "Travel Intention (TravelIntent)",
                       sp$title,
                       as.numeric(t$estimate), p_raw[i], p_holm[i])
  out_path <- here("outputs", sp$file)
  ggsave(out_path, p, width = 6, height = 5, dpi = 150)
  cat("Saved:", sp$file, "\n")
}
cat("\n")


# ── Section 8: Reliability ───────────────────────────────────
# Cronbach's alpha is used for multi-item scales (SMuse: 4 items,
# TravelIntent: 5 items) where alpha is an appropriate measure.
#
# For the five 2-item BFI composites, Spearman-Brown (SB) is used instead.
# Alpha is mathematically identical to SB for 2-item scales only when items
# have equal variance, which is not guaranteed. SB = (2*r) / (1 + r) where
# r is the inter-item Pearson correlation. Threshold: SB > 0.70 acceptable.

cat("── Reliability ─────────────────────────────────────────\n\n")

# Cronbach's alpha — SMuse and TravelIntent only
cat("  Cronbach's alpha (multi-item scales, α > 0.70 acceptable):\n")
alpha_scales <- list(
  SMuse        = df %>% select(Q1, Q2, Q3, Q4),
  TravelIntent = df %>% select(Q5, Q6, Q7, Q8, Q9)
)
for (scale_name in names(alpha_scales)) {
  a         <- psych::alpha(alpha_scales[[scale_name]], warnings = FALSE)
  alpha_val <- a$total$raw_alpha
  flag      <- ifelse(alpha_val >= 0.70, "✓ acceptable", "✗ below threshold")
  cat(sprintf("    %-16s α = %.3f  %s\n", scale_name, alpha_val, flag))
}

cat("\n  Spearman-Brown coefficient (2-item BFI scales, SB > 0.70 acceptable):\n")
cat("  [CIs for Spearman-Brown require bootstrapping and are not reported here.]\n")

sb_scales <- list(
  Openness          = c("Q10",  "Q11_r"),
  Extraversion      = c("Q12",  "Q13_r"),
  Agreeableness     = c("Q14",  "Q15_r"),
  Conscientiousness = c("Q16",  "Q17_r"),
  Neuroticism       = c("Q18",  "Q19_r")
)
for (scale_name in names(sb_scales)) {
  items <- sb_scales[[scale_name]]
  r_ii  <- cor(df[[items[1]]], df[[items[2]]], use = "complete.obs")
  sb    <- (2 * r_ii) / (1 + r_ii)
  flag  <- ifelse(sb >= 0.70, "✓ acceptable", "✗ below threshold — interpret with caution")
  cat(sprintf("    %-20s r_ii = %.3f  SB = %.3f  %s\n", scale_name, r_ii, sb, flag))
}

cat("\n── Analysis complete. All outputs saved to outputs/ ────\n")
