## ============================================================
## Go8 Internal Carbon Pricing (ICP) Readiness Assessment
## Reproducible analysis script
## Source data: 18-variable weighted scoring rubric applied to
## all 8 Group of Eight universities (see /data/go8_icp_raw_scores.csv)
## ============================================================

library(dplyr)
library(tidyr)
library(ggplot2)
library(forcats)

raw <- read.csv("data/go8_icp_raw_scores.csv", stringsAsFactors = FALSE)

## ------------------------------------------------------------
## 1. Compute weighted variable scores, then roll up to dimension level
## ------------------------------------------------------------
raw <- raw %>%
  mutate(weighted_score = raw_score * weight,
         weighted_max   = max_score * weight)

dim_scores <- raw %>%
  group_by(university, dimension) %>%
  summarise(score = sum(weighted_score),
            max   = sum(weighted_max),
            pct   = round(100 * score / max, 1),
            .groups = "drop")

## Wide format mirrors Table 3 / Appendix A.2 in the thesis
dim_wide <- dim_scores %>%
  select(university, dimension, score) %>%
  pivot_wider(names_from = dimension, values_from = score)

totals <- dim_scores %>%
  group_by(university) %>%
  summarise(total_score = sum(score),
            total_max   = sum(max),
            total_pct   = round(100 * total_score / total_max, 1),
            .groups = "drop")

## ------------------------------------------------------------
## 2. Apply the two-pass ICP allocation logic
##    Hard Barrier 1: Emissions Accounting < 40% -> Proxy
##    Hard Barrier 2: Operational Autonomy < 40% -> Proxy
##    Otherwise allocate by total score band
## ------------------------------------------------------------
ea_pct  <- dim_scores %>% filter(dimension == "Emissions Accounting") %>%
  select(university, ea_pct = pct)
ops_pct <- dim_scores %>% filter(dimension == "Operational Autonomy") %>%
  select(university, ops_pct = pct)

results <- totals %>%
  left_join(ea_pct, by = "university") %>%
  left_join(ops_pct, by = "university") %>%
  mutate(
    barrier1 = ea_pct  < 40,
    barrier2 = ops_pct < 40,
    icp_recommendation = case_when(
      barrier1 | barrier2          ~ "Proxy Carbon Price",
      total_pct >= 76               ~ "Hybrid System",
      total_pct >= 59               ~ "Carbon Fee / Flat Contribution",
      total_pct >= 39               ~ "Organisational Carbon Fund",
      TRUE                          ~ "Proxy Carbon Price"
    )
  ) %>%
  arrange(desc(total_pct))

cat("\n=== Go8 ICP Readiness — Reproduced Table 3 ===\n\n")
print(results %>% select(university, total_score, total_pct,
                          ea_pct, ops_pct, icp_recommendation),
      row.names = FALSE)

write.csv(results, "data/go8_icp_results_summary.csv", row.names = FALSE)
write.csv(dim_wide %>% left_join(totals, by = "university"),
          "data/go8_icp_dimension_scores.csv", row.names = FALSE)

## ------------------------------------------------------------
## 3. Figure 1 — Total readiness score by university, coloured by
##    ICP recommendation (the headline chart)
## ------------------------------------------------------------
fig1_data <- results %>%
  mutate(university = fct_reorder(university, total_pct))

p1 <- ggplot(fig1_data, aes(x = university, y = total_pct, fill = icp_recommendation)) +
  geom_col(width = 0.65) +
  geom_hline(yintercept = 40, linetype = "dashed", color = "grey40") +
  geom_text(aes(label = paste0(total_pct, "%")), hjust = -0.15, size = 3.5) +
  coord_flip(clip = "off") +
  scale_y_continuous(limits = c(0, 100), expand = expansion(mult = c(0, 0.12))) +
  scale_fill_manual(values = c(
    "Proxy Carbon Price" = "#D4A03C",
    "Carbon Fee / Flat Contribution" = "#2E6F5E",
    "Organisational Carbon Fund" = "#5B7DB1",
    "Hybrid System" = "#7B4B94"
  )) +
  labs(
    title = "Overall ICP readiness score does not determine the recommendation",
    subtitle = "Recommendation is set by hard-barrier conditions, not total score alone",
    x = NULL, y = "Total weighted readiness score (% of 55 points)",
    fill = "ICP recommendation"
  ) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom",
        plot.title = element_text(face = "bold"))

ggsave("figures/01_total_score_by_recommendation.png", p1, width = 9, height = 5.5, dpi = 200)

## ------------------------------------------------------------
## 4. Figure 2 — Dimension comparison (grouped bars), showing the
##    governance/policy vs. accounting/autonomy gap
## ------------------------------------------------------------
dim_pct <- dim_scores %>%
  mutate(dimension = factor(dimension, levels = c(
    "Emissions Accounting", "Governance", "Operational Autonomy", "Policy & Regulatory"
  )))

uni_order <- results$university

p2 <- ggplot(dim_pct, aes(x = factor(university, levels = uni_order), y = pct, fill = dimension)) +
  geom_col(position = position_dodge(width = 0.75), width = 0.7) +
  geom_hline(yintercept = 40, linetype = "dashed", color = "grey40") +
  scale_fill_manual(values = c(
    "Emissions Accounting" = "#2E6F5E",
    "Governance" = "#5B7DB1",
    "Operational Autonomy" = "#D4574A",
    "Policy & Regulatory" = "#D4A03C"
  )) +
  labs(
    title = "Governance commitments consistently outpace operational capacity",
    subtitle = "Dashed line = 40% hard-barrier threshold (Gorbach et al., 2022)",
    x = NULL, y = "Dimension score (% of dimension maximum)", fill = "Dimension"
  ) +
  theme_minimal(base_size = 12) +
  theme(axis.text.x = element_text(angle = 30, hjust = 1),
        legend.position = "bottom",
        plot.title = element_text(face = "bold"))

ggsave("figures/02_dimension_comparison.png", p2, width = 10, height = 6, dpi = 200)

## ------------------------------------------------------------
## 5. Figure 3 — Variable-level heatmap (all 18 variables x 8 universities)
## ------------------------------------------------------------
heat_data <- raw %>%
  mutate(pct_of_max = round(100 * raw_score / max_score, 0),
         variable = factor(variable, levels = c(
           "EA1","EA2","EA3","EA4","EA5",
           "G1","G2","G3","G4","G5",
           "O1","O2","O3","O4",
           "P1","P2","P3","P4"
         )))

p3 <- ggplot(heat_data, aes(x = variable, y = factor(university, levels = rev(uni_order)), fill = pct_of_max)) +
  geom_tile(color = "white", linewidth = 0.6) +
  scale_fill_gradient2(low = "#D4574A", mid = "#F2E3B3", high = "#2E6F5E",
                        midpoint = 50, name = "% of\nmax score") +
  labs(
    title = "Variable-level scoring detail across all 18 rubric items",
    subtitle = "Cost-centre allocation (EA4) and utility billing (O2) are near-zero across the entire sector",
    x = NULL, y = NULL
  ) +
  theme_minimal(base_size = 12) +
  theme(plot.title = element_text(face = "bold"),
        panel.grid = element_blank())

ggsave("figures/03_variable_heatmap.png", p3, width = 11, height = 5.5, dpi = 200)

cat("\nFigures written to /figures. Summary CSVs written to /data.\n")
