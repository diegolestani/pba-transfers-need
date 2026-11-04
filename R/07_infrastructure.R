# 07_infrastructure.R
# Network infrastructure (piped public water and public sewer) by tract deprivation,
# within/between-partido variation, and how infrastructure deficits relate to transfers.
# Inputs : data/processed/tracts.gpkg, data/processed/partidos.gpkg,
#          output/tables/transfers_2025_partido.csv
# Outputs: output/tables/infrastructure_by_quintile.csv, output/tables/infrastructure_summary.csv,
#          output/figures/fig8_infrastructure_by_quintile.png
suppressPackageStartupMessages({library(sf); library(dplyr); library(tidyr); library(ggplot2)})
sf_use_s2(FALSE)

td <- st_read("data/processed/tracts.gpkg", quiet = TRUE) |> st_drop_geometry() |> filter(hog_total > 0)

# Household-weighted quintiles of tracts by NBI share (Q1 least deprived), as in 05_access.R
td <- td |> arrange(nbi_share) |>
  mutate(cum = cumsum(pob_total) / sum(pob_total), nbi_q = pmin(5, floor(cum * 5 - 1e-9) + 1),
         area = ifelse(gba24, "Greater Buenos Aires", "Rest of province"))
byq <- td |> group_by(area, nbi_q) |>
  summarise(households = sum(hog_total),
            water_net = sum(agua_red) / sum(hog_total),
            sewer_net = sum(desague_red) / sum(hog_total), .groups = "drop")

# Within-partido share of variation in the share of households WITHOUT each network
decomp <- function(d, y) {
  w <- d$hog_total; mu <- weighted.mean(y, w)
  mu_p <- ave(y * w, d$cod_partido, FUN = sum) / ave(w, d$cod_partido, FUN = sum)
  tot <- sum(w * (y - mu)^2); 100 * (tot - sum(w * (mu_p - mu)^2)) / tot
}

# Partido level: concentration of infrastructure deficits vs. transfers (most deficient first)
p <- st_read("data/processed/partidos.gpkg", quiet = TRUE) |> st_drop_geometry()
trf <- read.csv("output/tables/transfers_2025_partido.csv", colClasses = c(cod_partido = "character"))
p <- left_join(p, trf[, c("cod_partido", "tr_total", "tr_pc")], by = "cod_partido") |>
  mutate(hh_no_sewer = hog_total - hog_desague_red, no_sewer_share = hh_no_sewer / hog_total)
conc <- function(df, rank_var, value) {
  df <- df[order(-df[[rank_var]]), ]
  w <- df$pob_total / sum(df$pob_total); v <- df[[value]] / sum(df[[value]])
  L <- cumsum(v); 1 - sum(w * (L + c(0, head(L, -1))))
}
summ <- data.frame(
  indicator = c("Piped public water (province)", "Public sewer (province)",
                "Within-partido share of variance, no piped water (%)",
                "Within-partido share of variance, no sewer (%)",
                "Concentration coefficient: households without sewer (ranked by sewer deficit)",
                "Concentration coefficient: transfers (ranked by sewer deficit)",
                "Correlation: partido NBI share vs. no-sewer share"),
  value = c(sum(td$agua_red) / sum(td$hog_total), sum(td$desague_red) / sum(td$hog_total),
            decomp(td, 1 - td$water_net_share), decomp(td, 1 - td$sewer_net_share),
            conc(p, "no_sewer_share", "hh_no_sewer"), conc(p, "no_sewer_share", "tr_total"),
            cor(p$nbi_share, p$no_sewer_share)))
write.csv(byq, "output/tables/infrastructure_by_quintile.csv", row.names = FALSE)
write.csv(summ, "output/tables/infrastructure_summary.csv", row.names = FALSE)

# Figure 8
pl <- byq |> pivot_longer(c(water_net, sewer_net), names_to = "network", values_to = "share") |>
  mutate(network = ifelse(network == "water_net", "Piped public water", "Public sewer connection"))
fig8 <- ggplot(pl, aes(factor(nbi_q), share, fill = area)) +
  geom_col(position = position_dodge(width = 0.75), width = 0.7) +
  facet_wrap(~ network) +
  scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
  scale_fill_manual(values = c("Greater Buenos Aires" = "#c94a3a", "Rest of province" = "#3d5a8a"), name = NULL) +
  scale_x_discrete(labels = c("Q1\nleast\ndeprived", "Q2", "Q3", "Q4", "Q5\nmost\ndeprived")) +
  labs(title = "Sewer networks are missing where deprivation is concentrated",
       subtitle = "Share of households connected, by population quintile of census tracts ranked by share of households with NBI.",
       x = NULL, y = "Households connected",
       caption = "Households without a toilet are counted as not connected to the sewer. Source: INDEC, Censo 2022 (REDATAM).") +
  theme_minimal(base_size = 10) +
  theme(legend.position = "top", plot.title = element_text(face = "bold", size = 12), plot.title.position = "plot",
        panel.grid.major.x = element_blank())
ggsave("output/figures/fig8_infrastructure_by_quintile.png", fig8, width = 9, height = 5.5, dpi = 200, bg = "white")

print(as.data.frame(byq), digits = 2); print(summ, digits = 3)
