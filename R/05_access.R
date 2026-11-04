# 05_access.R
# Spatial access to public health facilities by deprivation.
# Straight-line distance from each census tract to the nearest public general hospital
# (inpatient) and the nearest primary care centre (CAPS), weighted by population.
# Inputs : data/raw/establecimientos_salud_publicos-2025.csv (Buenos Aires open data portal)
#          data/processed/tracts.gpkg, data/processed/partidos.gpkg,
#          output/tables/transfers_2025_partido.csv (from 04_transfers.R)
# Outputs: output/tables/access_by_quintile.csv, output/tables/hospitals_partido.csv,
#          output/tables/regression_transfers_hospitals.csv,
#          output/figures/fig6_access_by_quintile.png
suppressPackageStartupMessages({library(sf); library(dplyr); library(readr); library(ggplot2)})
sf_use_s2(FALSE)
CRS_PBA <- "+proj=aea +lat_1=-34 +lat_2=-39 +lat_0=-37 +lon_0=-60 +datum=WGS84 +units=m +no_defs"

fac <- read_delim("data/raw/establecimientos_salud_publicos-2025.csv", delim = ";",
                  locale = locale(encoding = "UTF-8"), col_types = cols(.default = "c"),
                  show_col_types = FALSE) |>
  mutate(lat = as.numeric(lat), long = as.numeric(long),
         type = case_when(
           mod == "ASISTENCIAL CON INTERNACION" & Esp == "GENERAL" ~ "hospital",  # general inpatient
           cat == "C.A.P.S."                                         ~ "caps",      # primary care
           TRUE ~ NA_character_)) |>
  filter(!is.na(type)) |>
  st_as_sf(coords = c("long", "lat"), crs = 4326) |>
  st_transform(CRS_PBA)

tracts   <- st_read("data/processed/tracts.gpkg", quiet = TRUE) |> filter(pob_total > 0)
partidos <- st_read("data/processed/partidos.gpkg", quiet = TRUE)

# Tract representative point (guaranteed to fall inside the polygon)
pts <- st_point_on_surface(st_geometry(tracts))
nearest_km <- function(from, to) {
  idx <- st_nearest_feature(from, to)
  as.numeric(st_distance(from, to[idx, ], by_element = TRUE)) / 1000
}
tracts$dist_hosp_km <- nearest_km(pts, filter(fac, type == "hospital"))
tracts$dist_caps_km <- nearest_km(pts, filter(fac, type == "caps"))

# Population-weighted quintiles of tracts by NBI share (Q1 = least deprived, Q5 = most deprived)
td <- st_drop_geometry(tracts) |>
  arrange(nbi_share) |>
  mutate(cum_pop = cumsum(pob_total) / sum(pob_total),
         nbi_q = pmin(5, floor(cum_pop * 5 - 1e-9) + 1))
wmean <- function(x, w) sum(x * w) / sum(w)
acc <- td |>
  mutate(area = ifelse(gba24, "Greater Buenos Aires", "Rest of province")) |>
  group_by(area, nbi_q) |>
  summarise(pop = sum(pob_total), nbi_share = sum(hog_nbi) / sum(hog_total),
            share_far_hosp = wmean(dist_hosp_km > 5, pob_total),   # computed before the means overwrite the columns
            share_far_caps = wmean(dist_caps_km > 2, pob_total),
            dist_hosp_km = wmean(dist_hosp_km, pob_total),
            dist_caps_km = wmean(dist_caps_km, pob_total), .groups = "drop")

# Facilities by partido (spatial join), to relate service provision to transfers
fac_p <- st_join(fac, select(partidos, cod_partido)) |>
  st_drop_geometry() |>
  count(cod_partido, type) |>
  tidyr::pivot_wider(names_from = type, values_from = n, values_fill = 0)
hosp_p <- st_drop_geometry(partidos) |>
  select(cod_partido, partido, gba24, pob_total, nbi_share) |>
  left_join(fac_p, by = "cod_partido") |>
  mutate(across(c(hospital, caps), ~ coalesce(.x, 0)),
         hosp_per_100k = 1e5 * hospital / pob_total,
         caps_per_100k = 1e5 * caps / pob_total)

# Does hospital provision explain per capita transfers? (the coparticipación formula rewards health services)
trf <- read.csv("output/tables/transfers_2025_partido.csv", colClasses = c(cod_partido = "character"))
m <- lm(log(tr_pc) ~ log(pob_total) + nbi_share + log(hosp_per_100k + 1),
        merge(hosp_p, trf[, c("cod_partido", "tr_pc")], by = "cod_partido"))
co <- summary(m)$coefficients
readr::write_csv(data.frame(term = rownames(co), estimate = co[, 1], std_error = co[, 2], p_value = co[, 4],
                     r2 = summary(m)$r.squared, n = nobs(m)),
          "output/tables/regression_transfers_hospitals.csv")

readr::write_csv(acc, "output/tables/access_by_quintile.csv")
readr::write_csv(hosp_p, "output/tables/hospitals_partido.csv")
st_write(select(tracts, cod_radio, dist_hosp_km, dist_caps_km),
         "data/processed/tract_access.gpkg", quiet = TRUE, delete_dsn = TRUE)

# Figure 6
pl <- tidyr::pivot_longer(acc, c(dist_hosp_km, dist_caps_km), names_to = "facility", values_to = "km") |>
  mutate(facility = ifelse(facility == "dist_hosp_km", "Nearest public general hospital",
                           "Nearest primary care centre (CAPS)"))
fig6 <- ggplot(pl, aes(factor(nbi_q), km, fill = area)) +
  geom_col(position = position_dodge(width = 0.75), width = 0.7) +
  facet_wrap(~ facility, scales = "free_y") +
  scale_fill_manual(values = c("Greater Buenos Aires" = "#c94a3a", "Rest of province" = "#3d5a8a"), name = NULL) +
  scale_x_discrete(labels = c("Q1\nleast\ndeprived", "Q2", "Q3", "Q4", "Q5\nmost\ndeprived")) +
  labs(title = "Primary care reaches deprived tracts; public hospitals are farther from them",
       subtitle = "Population-weighted average straight-line distance (km). Tracts grouped into population quintiles by share of households with NBI.",
       x = NULL, y = "km",
       caption = "Straight-line distance from each tract's representative point; road-network travel time would be larger, especially in rural areas.\nSource: Buenos Aires Ministry of Health facility registry (2025); INDEC, Censo 2022.") +
  theme_minimal(base_size = 10) +
  theme(legend.position = "top", plot.title = element_text(face = "bold", size = 12), plot.title.position = "plot",
        panel.grid.major.x = element_blank())
ggsave("output/figures/fig6_access_by_quintile.png", fig6, width = 9, height = 5.5, dpi = 200, bg = "white")

cat(sprintf("Facilities: %d general hospitals, %d CAPS\n", sum(fac$type == "hospital"), sum(fac$type == "caps")))
print(as.data.frame(acc), digits = 2)
