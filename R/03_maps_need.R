# 03_maps_need.R
# Figure 1: share of households with NBI by census tract (province and Greater Buenos Aires)
# Figure 2: partido averages vs. the spread of tract NBI rates within each partido
# Inputs : data/processed/tracts.gpkg, data/processed/partidos.gpkg
# Outputs: output/figures/fig1_nbi_tracts.png, output/figures/fig2_within_partido_spread.png
suppressPackageStartupMessages({library(sf); library(dplyr); library(ggplot2); library(patchwork)})
sf_use_s2(FALSE)

tracts   <- st_read("data/processed/tracts.gpkg", quiet = TRUE)
partidos <- st_read("data/processed/partidos.gpkg", quiet = TRUE)

breaks <- c(0, 0.02, 0.05, 0.10, 0.20, 1)
labels <- c("< 2%", "2-5%", "5-10%", "10-20%", "20% or more", "No households")
pal    <- setNames(c("#f2efe9", "#f6c99a", "#ec8a5b", "#c94a3a", "#7a1c2e", "grey85"), labels)
tracts <- tracts |>
  mutate(nbi_class = cut(nbi_share, breaks, labels[1:5], include.lowest = TRUE, right = FALSE),
         nbi_class = factor(ifelse(is.na(nbi_class), "No households", as.character(nbi_class)), levels = labels))

map_layer <- function(t, p) {
  ggplot() +
    geom_sf(data = t, aes(fill = nbi_class, alpha = urban_rural), colour = NA) +
    geom_sf(data = p, fill = NA, colour = "grey25", linewidth = 0.15) +
    scale_fill_manual(values = pal, drop = FALSE, name = "Households with NBI") +
    scale_alpha_manual(values = c(U = 1, R = 0.35), guide = "none") +
    theme_void(base_size = 10)
}

partidos <- partidos |>
  mutate(nbi_class = factor(as.character(cut(nbi_share, breaks, labels[1:5], include.lowest = TRUE, right = FALSE)),
                            levels = labels))
gba_t <- filter(tracts, gba24); gba_p <- filter(partidos, gba24)
p0 <- ggplot() +
  geom_sf(data = partidos, aes(fill = nbi_class), colour = "grey25", linewidth = 0.15) +
  scale_fill_manual(values = pal, drop = FALSE, name = "Households with NBI") +
  theme_void(base_size = 10)
p1 <- p0 + guides(fill = "none") + labs(subtitle = "What a partido-level view shows: all 135 partidos below 13%")
p2 <- map_layer(gba_t, gba_p) + labs(subtitle = "What census tracts show: Greater Buenos Aires (24 partidos)")
fig1 <- (p1 | p2) + plot_layout(guides = "collect", widths = c(1.15, 1)) +
  plot_annotation(
    title = "Deprivation is concentrated at a much finer scale than the partido",
    caption = "Share of households with Unmet Basic Needs (NBI). Left: partido averages. Right: census tracts (radio censal); rural tracts are faded because they cover large areas with few households.\nSource: INDEC, Censo 2022 (REDATAM); tract boundaries from the Buenos Aires open data portal.") &
  theme(legend.position = "bottom", plot.title = element_text(face = "bold", size = 12))
ggsave("output/figures/fig1_nbi_tracts.png", fig1, width = 11, height = 6.5, dpi = 200, bg = "white")

# Figure 2: 30 largest partidos by households
top <- st_drop_geometry(partidos) |> slice_max(hog_total, n = 30) |>
  mutate(partido = reorder(partido, nbi_share))
fig2 <- ggplot(top, aes(y = partido)) +
  geom_segment(aes(x = nbi_p10, xend = nbi_p90, yend = partido), colour = "grey70", linewidth = 2.2) +
  geom_point(aes(x = nbi_share, colour = gba24), size = 2.4) +
  scale_x_continuous(labels = scales::percent, expand = expansion(mult = c(0.01, 0.05))) +
  scale_colour_manual(values = c(`TRUE` = "#c94a3a", `FALSE` = "#3d5a8a"),
                      labels = c(`TRUE` = "Greater Buenos Aires", `FALSE` = "Rest of province"), name = NULL) +
  labs(title = "Partido averages hide large differences between neighbourhoods",
       subtitle = "Dot: partido share of households with NBI. Bar: 10th-90th percentile of tract rates within the partido (household-weighted).",
       x = "Households with NBI", y = NULL,
       caption = "30 largest partidos by number of households. Source: INDEC, Censo 2022.") +
  theme_minimal(base_size = 10) +
  theme(legend.position = "top", panel.grid.major.y = element_blank(),
        plot.title = element_text(face = "bold", size = 12), plot.title.position = "plot")
ggsave("output/figures/fig2_within_partido_spread.png", fig2, width = 8, height = 7.5, dpi = 200, bg = "white")
cat("Figures written to output/figures/\n")
