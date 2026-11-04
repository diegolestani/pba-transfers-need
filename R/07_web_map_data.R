# 07_web_map_data.R
# Export simplified, lightweight GeoJSON layers for the interactive web map (docs/index.html)
# Inputs : data/processed/tracts.gpkg, data/processed/partidos.gpkg,
#          output/tables/transfers_2025_partido.csv, output/tables/hospitals_partido.csv,
#          data/raw/establecimientos_salud_publicos-2025.csv
# Outputs: docs/data/tracts.geojson, docs/data/partidos.geojson, docs/data/facilities.geojson
suppressPackageStartupMessages({library(sf); library(dplyr); library(readr)})
sf_use_s2(FALSE)

# After repair, st_collection_extract can split one feature into several rows; merge them back by id
aggregate_parts <- function(x) {
  if (!anyDuplicated(x$id)) return(x)
  geom <- st_geometry(x); attrs <- st_drop_geometry(x)
  g <- tapply(seq_len(nrow(x)), x$id, function(i) st_union(geom[i]))
  keep <- !duplicated(x$id)
  out <- st_sf(attrs[keep, , drop = FALSE], geometry = do.call(c, g[x$id[keep]]))
  st_cast(out, "MULTIPOLYGON")
}

write_geojson <- function(x, path, digits = 5) {
  if (file.exists(path)) file.remove(path)
  if (all(st_geometry_type(x) %in% c("POLYGON", "MULTIPOLYGON"))) {
    # Round to the output precision first, then repair: rounding can collapse thin slivers into
    # lines or points, which would otherwise be written as GeometryCollections
    x <- st_set_precision(x, 10^digits) |> st_make_valid() |>
      st_collection_extract("POLYGON") |> st_cast("MULTIPOLYGON")
    x <- aggregate_parts(x)
  }
  st_write(x, path, driver = "GeoJSON", quiet = TRUE,
           layer_options = c(paste0("COORDINATE_PRECISION=", digits + 1)))
}

# Census tracts: simplify in metres, then back to WGS84
tracts <- st_read("data/processed/tracts.gpkg", quiet = TRUE) |>
  filter(hog_total > 0) |>
  st_simplify(preserveTopology = TRUE, dTolerance = 40) |>
  st_collection_extract("POLYGON") |> st_cast("MULTIPOLYGON") |>
  transmute(id = cod_radio, p = partido, ur = urban_rural,
            n = round(100 * nbi_share, 1), i = round(100 * ipmh_corr_share, 1),
            h = hog_total) |>
  st_transform(4326)
write_geojson(tracts, "docs/data/tracts.geojson", digits = 4)

trf <- read.csv("output/tables/transfers_2025_partido.csv", colClasses = c(cod_partido = "character"))
hos <- read.csv("output/tables/hospitals_partido.csv", colClasses = c(cod_partido = "character"))
partidos <- st_read("data/processed/partidos.gpkg", quiet = TRUE) |>
  st_simplify(preserveTopology = TRUE, dTolerance = 100) |>
  st_collection_extract("POLYGON") |> st_cast("MULTIPOLYGON") |>
  select(cod_partido, partido, gba24) |>
  left_join(trf |> select(cod_partido, pob_total, nbi_share, ipmh_corr_share, tr_pc, gap_blend), by = "cod_partido") |>
  left_join(hos |> select(cod_partido, hospital, caps), by = "cod_partido") |>
  transmute(id = cod_partido, p = partido, gba = gba24, pop = pob_total,
            n = round(100 * nbi_share, 1), i = round(100 * ipmh_corr_share, 1),
            tpc = round(tr_pc), gap = round(100 * gap_blend), hos = hospital, caps = caps) |>
  st_transform(4326)
write_geojson(partidos, "docs/data/partidos.geojson")

fac <- read_delim("data/raw/establecimientos_salud_publicos-2025.csv", delim = ";",
                  locale = locale(encoding = "UTF-8"), col_types = cols(.default = "c"),
                  show_col_types = FALSE) |>
  mutate(t = case_when(mod == "ASISTENCIAL CON INTERNACION" & Esp == "GENERAL" ~ "H",
                       cat == "C.A.P.S." ~ "C", TRUE ~ NA_character_)) |>
  filter(!is.na(t)) |>
  transmute(t, nm = tools::toTitleCase(tolower(nor)), dep = tes,
            lat = as.numeric(lat), long = as.numeric(long)) |>
  st_as_sf(coords = c("long", "lat"), crs = 4326)
write_geojson(fac, "docs/data/facilities.geojson")

for (f in list.files("docs/data", full.names = TRUE))
  cat(sprintf("%-32s %6.1f MB\n", f, file.size(f) / 1e6))
