# 08_nightlights.R
# Nighttime lights (VIIRS annual 2022) by census tract: zonal statistics, and how well light
# intensity tracks deprivation across and within partidos.
# Inputs : data/raw/viirs_ntl_2022_pba.tif (exported with gee/viirs_ntl_2022_export.js)
#          data/processed/tracts.gpkg
# Outputs: data/processed/tract_ntl.csv, output/tables/ntl_fit.csv,
#          output/figures/fig9_nightlights_vs_nbi.png
suppressPackageStartupMessages({library(sf); library(terra); library(exactextractr); library(dplyr); library(ggplot2)})
sf_use_s2(FALSE)

ntl <- rast("data/raw/viirs_ntl_2022_pba.tif")
tracts <- st_read("data/processed/tracts.gpkg", quiet = TRUE) |> filter(hog_total > 0)

# Area-weighted mean radiance per tract (exact pixel coverage fractions; small tracts get
# the value of the pixel(s) they fall in)
tw <- st_transform(tracts, crs(ntl))
tracts$ntl_mean <- exact_extract(ntl, tw, "mean", progress = FALSE)
tracts$log_ntl <- log1p(tracts$ntl_mean)
td <- st_drop_geometry(tracts)
readr::write_csv(td[, c("cod_radio", "ntl_mean")], "data/processed/tract_ntl.csv")

# How much of the variation in tract NBI rates does light intensity explain?
# (household-weighted; with partido fixed effects = within-partido explanatory power)
fit <- function(d, label) {
  m0 <- lm(nbi_share ~ log_ntl, d, weights = hog_total)
  m1 <- lm(nbi_share ~ log_ntl + factor(cod_partido), d, weights = hog_total)
  m1b <- lm(nbi_share ~ factor(cod_partido), d, weights = hog_total)
  data.frame(sample = label, tracts = nrow(d),
             slope = coef(m0)[["log_ntl"]], r2 = summary(m0)$r.squared,
             slope_within = coef(m1)[["log_ntl"]],
             within_r2_gain = summary(m1)$r.squared - summary(m1b)$r.squared)
}
res <- rbind(fit(td, "All tracts"), fit(td[td$gba24, ], "Greater Buenos Aires"),
             fit(td[!td$gba24 & td$urban_rural == "U", ], "Urban tracts, rest of province"))
readr::write_csv(res, "output/tables/ntl_fit.csv")

# Figure 9: binned scatter (20 household-weighted bins of radiance), by area
td <- td |> mutate(area = ifelse(gba24, "Greater Buenos Aires", "Rest of province")) |>
  group_by(area) |> arrange(log_ntl) |>
  mutate(bin = pmin(20, floor(cumsum(hog_total) / sum(hog_total) * 20) + 1)) |> ungroup()
bins <- td |> group_by(area, bin) |>
  summarise(ntl = weighted.mean(ntl_mean, hog_total), nbi = sum(hog_nbi) / sum(hog_total), .groups = "drop")
fig9 <- ggplot(bins, aes(ntl, nbi, colour = area)) +
  geom_point(size = 2.4) + geom_line(alpha = 0.5) +
  scale_x_log10() + scale_y_continuous(labels = scales::percent) +
  scale_colour_manual(values = c("Greater Buenos Aires" = "#c94a3a", "Rest of province" = "#3d5a8a"), name = NULL) +
  labs(title = "Nighttime lights flag the dark urban fringe but explain little of deprivation",
       subtitle = "Share of households with NBI by bins of tract nighttime radiance (20 household-weighted bins per area).",
       x = "Mean nighttime radiance, 2022 (nW/cm\u00b2/sr, log scale)", y = "Households with NBI",
       caption = "VIIRS annual composite V2.2 (average_masked), Earth Observation Group, via Google Earth Engine; INDEC, Censo 2022.") +
  theme_minimal(base_size = 10) +
  theme(legend.position = "top", plot.title = element_text(face = "bold", size = 12), plot.title.position = "plot")
ggsave("output/figures/fig9_nightlights_vs_nbi.png", fig9, width = 8.5, height = 5.5, dpi = 200, bg = "white")

print(res, digits = 3)
print(as.data.frame(bins), digits = 2)
