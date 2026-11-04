# 06_spatial_dependence.R
# Spatial clustering of deprivation (global and local Moran's I at tract level) and of
# transfers per capita (partido level), plus a robustness check on the within-partido share.
# Inputs : data/processed/tracts.gpkg, data/processed/partidos.gpkg,
#          output/tables/transfers_2025_partido.csv
# Outputs: output/tables/morans_i.csv, output/tables/variance_decomposition_robustness.csv,
#          output/figures/fig7_lisa_gba.png
suppressPackageStartupMessages({library(sf); library(dplyr); library(spdep); library(ggplot2)})
sf_use_s2(FALSE)
set.seed(20261103)

tracts <- st_read("data/processed/tracts.gpkg", quiet = TRUE) |> filter(hog_total > 0)

# --- Tract level: queen contiguity, row-standardised ---
nb <- poly2nb(tracts, queen = TRUE)
lw <- nb2listw(nb, style = "W", zero.policy = TRUE)
mi_nbi  <- moran.test(tracts$nbi_share, lw, zero.policy = TRUE)
mi_ipmh <- moran.test(tracts$ipmh_corr_share, lw, zero.policy = TRUE)

# Local Moran's I (LISA) with false discovery rate correction for multiple testing
lm_nbi <- localmoran(tracts$nbi_share, lw, zero.policy = TRUE)
z  <- as.numeric(scale(tracts$nbi_share))
lz <- lag.listw(lw, z, zero.policy = TRUE)
p_fdr <- p.adjust(lm_nbi[, 5], method = "fdr")
tracts$lisa <- case_when(
  p_fdr >= 0.05 ~ "Not significant",
  z > 0 & lz > 0 ~ "High-High (deprivation cluster)",
  z < 0 & lz < 0 ~ "Low-Low",
  z > 0 & lz < 0 ~ "High-Low",
  TRUE ~ "Low-High")

# --- Partido level: are transfers per capita and need spatially clustered? ---
partidos <- st_read("data/processed/partidos.gpkg", quiet = TRUE)
trf <- read.csv("output/tables/transfers_2025_partido.csv", colClasses = c(cod_partido = "character"))
partidos <- left_join(partidos, trf[, c("cod_partido", "tr_pc")], by = "cod_partido")
lw_p <- nb2listw(poly2nb(partidos, queen = TRUE), style = "W", zero.policy = TRUE)
mi_p_nbi <- moran.test(partidos$nbi_share, lw_p, zero.policy = TRUE)
mi_p_tr  <- moran.test(log(partidos$tr_pc), lw_p, zero.policy = TRUE)

mi <- data.frame(
  level = c("tract", "tract", "partido", "partido"),
  variable = c("NBI share", "IPMH current-resource share", "NBI share", "log transfers per capita"),
  morans_i = c(mi_nbi$estimate[1], mi_ipmh$estimate[1], mi_p_nbi$estimate[1], mi_p_tr$estimate[1]),
  p_value = c(mi_nbi$p.value, mi_ipmh$p.value, mi_p_nbi$p.value, mi_p_tr$p.value),
  n = c(nrow(tracts), nrow(tracts), nrow(partidos), nrow(partidos)))
write.csv(mi, "output/tables/morans_i.csv", row.names = FALSE)

# --- Robustness: within-partido share of variance, excluding small (noisy) tracts ---
decomp <- function(d, min_hh) {
  d <- d[d$hog_total >= min_hh, ]
  w <- d$hog_total; y <- d$nbi_share; mu <- weighted.mean(y, w)
  mu_p <- ave(y * w, d$cod_partido, FUN = sum) / ave(w, d$cod_partido, FUN = sum)
  tot <- sum(w * (y - mu)^2); btw <- sum(w * (mu_p - mu)^2)
  data.frame(min_households = min_hh, tracts = nrow(d), within_pct = 100 * (tot - btw) / tot)
}
td <- st_drop_geometry(tracts)
rob <- bind_rows(lapply(c(1, 50, 100, 200), function(m) decomp(td, m)))
write.csv(rob, "output/tables/variance_decomposition_robustness.csv", row.names = FALSE)

# --- Figure 7: LISA clusters, Greater Buenos Aires ---
gba <- filter(tracts, gba24)
gba_p <- filter(partidos, gba24)
cols <- c("High-High (deprivation cluster)" = "#7a1c2e", "Low-Low" = "#3d5a8a",
          "High-Low" = "#ec8a5b", "Low-High" = "#8aa6c8", "Not significant" = "#eeeeee")
fig7 <- ggplot() +
  geom_sf(data = gba, aes(fill = lisa, alpha = urban_rural), colour = NA) +
  geom_sf(data = gba_p, fill = NA, colour = "grey20", linewidth = 0.2) +
  scale_fill_manual(values = cols, name = NULL) +
  scale_alpha_manual(values = c(U = 1, R = 0.35), guide = "none") +
  labs(title = "Deprivation clusters cut across partido boundaries",
       subtitle = "Local Moran's I of the share of households with NBI, census tracts, Greater Buenos Aires.\nQueen contiguity; significance at 5% after false discovery rate correction.",
       caption = sprintf("Global Moran's I (all province tracts): %.2f. Rural tracts faded.\nSource: INDEC, Censo 2022; tract boundaries from the Buenos Aires open data portal.",
                         mi_nbi$estimate[1])) +
  theme_void(base_size = 10) +
  theme(legend.position = "right", plot.title = element_text(face = "bold", size = 12),
        plot.caption = element_text(hjust = 0), plot.margin = margin(10, 10, 10, 10))
ggsave("output/figures/fig7_lisa_gba.png", fig7, width = 9, height = 7.5, dpi = 200, bg = "white")

print(mi, digits = 3); print(rob, digits = 3)
print(table(tracts$lisa))
