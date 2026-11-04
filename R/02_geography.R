# 02_geography.R
# Join census tract boundaries (radios censales 2022) to census data, build partido
# aggregates, and measure how much deprivation varies within vs between partidos.
# Inputs : data/raw/radios-censales-2022-shp.zip   (Buenos Aires open data portal)
#          data/processed/census_radios.csv          (from 01_clean_census.R)
# Outputs: data/processed/tracts.gpkg, data/processed/partidos.gpkg,
#          output/tables/partidos_need.csv, output/tables/variance_decomposition.csv
suppressPackageStartupMessages({library(sf); library(dplyr)})
sf_use_s2(FALSE)

# Equal-area projection centred on Buenos Aires province (metres)
CRS_PBA <- "+proj=aea +lat_1=-34 +lat_2=-39 +lat_0=-37 +lon_0=-60 +datum=WGS84 +units=m +no_defs"

# 24 partidos of Greater Buenos Aires (INDEC definition)
GBA24 <- c("ALMIRANTE BROWN","AVELLANEDA","BERAZATEGUI","ESTEBAN ECHEVERRIA","EZEIZA",
           "FLORENCIO VARELA","GENERAL SAN MARTIN","HURLINGHAM","ITUZAINGO","JOSE C. PAZ",
           "LA MATANZA","LANUS","LOMAS DE ZAMORA","MALVINAS ARGENTINAS","MERLO","MORENO",
           "MORON","QUILMES","SAN FERNANDO","SAN ISIDRO","SAN MIGUEL","TIGRE",
           "TRES DE FEBRERO","VICENTE LOPEZ")

title_name <- function(x) {
  x <- tools::toTitleCase(tolower(x))
  x <- gsub("(?<= )De\\b", "de", x, perl = TRUE)      # "Lomas de Zamora"
  x <- gsub("(?<=de )La\\b", "la", x, perl = TRUE)    # "Exaltacion de la Cruz"
  x
}

tracts <- st_read("/vsizip/data/raw/radios-censales-2022-shp.zip/shp22/radios-censales.shp",
                  quiet = TRUE) |>
  transmute(cod_radio = LINK, cod_partido = paste0(PROV, DEPTO),
            partido_raw = NOMDEPTO, urban_rural = TIPO)

# The source file has a corrupted character in one name; fix by code
tracts$partido_raw[tracts$cod_partido == "06134"] <- "CA\u00d1UELAS"
tracts <- tracts |>
  mutate(partido = title_name(partido_raw), gba24 = partido_raw %in% GBA24,
         partido = ifelse(cod_partido == "06134", "Ca\u00f1uelas", partido)) |>
  st_make_valid() |>
  st_collection_extract("POLYGON") |>          # drop stray points/lines left by st_make_valid
  st_cast("MULTIPOLYGON") |>
  st_transform(CRS_PBA)
stopifnot(sum(GBA24 %in% tracts$partido_raw) == 24)

census <- read.csv("data/processed/census_radios.csv",
                   colClasses = c(cod_radio = "character", cod_partido = "character"))

# Every census tract must have a polygon; a few polygons have no census record (uninhabited)
stopifnot(all(census$cod_radio %in% tracts$cod_radio))
tracts <- tracts |>
  left_join(select(census, -cod_partido, -cod_prov, -cod_fraccion), by = "cod_radio") |>
  mutate(across(c(hog_total, hog_nbi, ipmh_corriente, ipmh_convergente, pob_total),
                ~ coalesce(.x, 0)),
         area_km2 = as.numeric(st_area(geometry)) / 1e6)

# Partido aggregates (polygons dissolved from tracts)
partidos <- tracts |>
  group_by(cod_partido, partido, gba24) |>
  summarise(hog_total = sum(hog_total), hog_nbi = sum(hog_nbi),
            hog_ipmh_corr = sum(ipmh_corriente + ipmh_convergente),
            pob_total = sum(pob_total), area_km2 = sum(area_km2),
            n_tracts = sum(hog_total > 0), .groups = "drop") |>
  mutate(nbi_share = hog_nbi / hog_total,
         ipmh_corr_share = hog_ipmh_corr / hog_total,
         density = pob_total / area_km2)
stopifnot(nrow(partidos) == 135)

# How much of the variation in tract NBI rates lies within partidos?
# Household-weighted decomposition: total variance = between-partido + within-partido
decompose <- function(d, share) {
  d <- d[d$hog_total > 0, ]
  w <- d$hog_total; y <- d[[share]]
  mu <- weighted.mean(y, w)
  mu_p <- ave(y * w, d$cod_partido, FUN = sum) / ave(w, d$cod_partido, FUN = sum)
  total <- sum(w * (y - mu)^2) / sum(w)
  between <- sum(w * (mu_p - mu)^2) / sum(w)
  data.frame(measure = share, total_var = total, between = between,
             within = total - between, within_pct = 100 * (total - between) / total)
}
td <- st_drop_geometry(tracts)
vd <- rbind(decompose(td, "nbi_share"), decompose(td, "ipmh_corr_share"))

# Within-partido spread: household-weighted 10th and 90th percentile of tract NBI rates
wq <- function(y, w, p) { o <- order(y); y <- y[o]; cw <- cumsum(w[o]) / sum(w); y[which(cw >= p)[1]] }
spread <- td |>
  filter(hog_total > 0) |>
  group_by(cod_partido) |>
  summarise(nbi_p10 = wq(nbi_share, hog_total, 0.10),
            nbi_p90 = wq(nbi_share, hog_total, 0.90),
            hh_in_high_nbi_tracts = sum(hog_total[nbi_share >= 0.20]) / sum(hog_total),
            .groups = "drop")
partidos <- left_join(partidos, spread, by = "cod_partido")

dir.create("output/tables", recursive = TRUE, showWarnings = FALSE)
st_write(tracts, "data/processed/tracts.gpkg", quiet = TRUE, delete_dsn = TRUE)
st_write(partidos, "data/processed/partidos.gpkg", quiet = TRUE, delete_dsn = TRUE)
write.csv(st_drop_geometry(partidos), "output/tables/partidos_need.csv", row.names = FALSE)
write.csv(vd, "output/tables/variance_decomposition.csv", row.names = FALSE)

cat(sprintf("Tracts: %d (%d with households) | Partidos: %d\n",
            nrow(tracts), sum(tracts$hog_total > 0), nrow(partidos)))
cat(sprintf("Share of tract-level variance that is within partidos: NBI %.0f%%, IPMH current %.0f%%\n",
            vd$within_pct[1], vd$within_pct[2]))
