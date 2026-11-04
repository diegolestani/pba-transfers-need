# 01_clean_census.R
# Clean INDEC Censo 2022 REDATAM exports (Lista de áreas, radio level, Buenos Aires province)
# Inputs : data/raw/NBI_tot_BA_2022.xlsx  (households by NBI status, per radio)
#          data/raw/Pop_Total_BA_2022.xlsx (population by sex, per radio)
#          data/raw/IPMH_BA_2022.xlsx      (households by material deprivation index, per radio)
#          data/raw/water_sewer_BA_2022.xlsx (households by water source and toilet drainage, per radio)
# Output : data/processed/census_radios.csv
suppressPackageStartupMessages({library(readxl); library(dplyr)})

read_redatam_list <- function(path, value_names) {
  x <- as.data.frame(read_excel(path, col_names = FALSE, .name_repair = "minimal"))
  keep <- grepl("^[0-9]+$", x[[2]])                      # rows with a radio code
  out <- x[keep, -1, drop = FALSE]
  names(out) <- c("cod_radio", value_names)
  out$cod_radio <- sprintf("%09.0f", as.numeric(out$cod_radio))  # restore leading zero (06 = Buenos Aires)
  out[value_names] <- lapply(out[value_names], as.numeric)
  out
}

nbi <- read_redatam_list("data/raw/NBI_tot_BA_2022.xlsx", c("hog_nbi", "hog_sin_nbi", "hog_total"))
pop <- read_redatam_list("data/raw/Pop_Total_BA_2022.xlsx", c("pob_mujer", "pob_varon", "pob_total"))
ipmh <- read_redatam_list("data/raw/IPMH_BA_2022.xlsx",
                          c("ipmh_sin", "ipmh_corriente", "ipmh_patrimonial", "ipmh_convergente", "ipmh_total"))

ws <- read_redatam_list("data/raw/water_sewer_BA_2022.xlsx",
                        c("agua_red", "agua_bomba_motor", "agua_bomba_manual", "agua_pozo", "agua_cisterna",
                          "agua_otra", "agua_total", "desague_red", "desague_camara", "desague_pozo",
                          "desague_hoyo", "desague_total"))

census <- nbi |>
  inner_join(pop, by = "cod_radio") |>
  inner_join(ipmh, by = "cod_radio") |>
  inner_join(select(ws, cod_radio, agua_red, desague_red), by = "cod_radio") |>
  mutate(
    cod_prov    = substr(cod_radio, 1, 2),
    cod_partido = substr(cod_radio, 1, 5),             # 5-digit INDEC department code (06 + 3)
    cod_fraccion= substr(cod_radio, 1, 7),
    nbi_share   = ifelse(hog_total > 0, hog_nbi / hog_total, NA_real_),
    # IPMH: deprivation of current resources (income proxy) = current-only + convergent
    ipmh_corr_share = ifelse(hog_total > 0, (ipmh_corriente + ipmh_convergente) / hog_total, NA_real_),
    # Network infrastructure: share of all households connected (households without a toilet count as not connected)
    water_net_share = ifelse(hog_total > 0, agua_red / hog_total, NA_real_),
    sewer_net_share = ifelse(hog_total > 0, desague_red / hog_total, NA_real_)
  ) |>
  select(cod_radio, cod_prov, cod_partido, cod_fraccion,
         hog_total, hog_nbi, nbi_share,
         ipmh_corriente, ipmh_convergente, ipmh_corr_share,
         agua_red, desague_red, water_net_share, sewer_net_share, pob_total)

stopifnot(nrow(census) == nrow(nbi), all(census$cod_prov == "06"),
          all(ipmh$ipmh_total == nbi$hog_total[match(ipmh$cod_radio, nbi$cod_radio)]),
          all(ws$agua_total == nbi$hog_total[match(ws$cod_radio, nbi$cod_radio)]),
          n_distinct(census$cod_partido) == 135)

readr::write_csv(census, "data/processed/census_radios.csv")
cat(sprintf("Radios: %d | Partidos: %d | Households: %s | NBI: %.1f%% | IPMH current-resource deprivation: %.1f%% | Piped water: %.1f%% | Sewer: %.1f%% | Population: %s\n",
            nrow(census), n_distinct(census$cod_partido),
            format(sum(census$hog_total), big.mark = ","),
            100 * sum(census$hog_nbi) / sum(census$hog_total),
            100 * sum(census$ipmh_corriente + census$ipmh_convergente) / sum(census$hog_total),
            100 * sum(census$agua_red) / sum(census$hog_total), 100 * sum(census$desague_red) / sum(census$hog_total),
            format(sum(census$pob_total), big.mark = ",")))
