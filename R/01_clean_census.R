# 01_clean_census.R
# Clean INDEC Censo 2022 REDATAM exports (Lista de áreas, radio level, Buenos Aires province)
# Inputs : data/raw/NBI_tot_BA_2022.xlsx  (households by NBI status, per radio)
#          data/raw/Pop_Total_BA_2022.xlsx (population by sex, per radio)
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

census <- nbi |>
  inner_join(pop, by = "cod_radio") |>
  mutate(
    cod_prov    = substr(cod_radio, 1, 2),
    cod_partido = substr(cod_radio, 1, 5),             # 5-digit INDEC department code (06 + 3)
    cod_fraccion= substr(cod_radio, 1, 7),
    nbi_share   = ifelse(hog_total > 0, hog_nbi / hog_total, NA_real_)
  ) |>
  select(cod_radio, cod_prov, cod_partido, cod_fraccion,
         hog_total, hog_nbi, nbi_share, pob_total)

stopifnot(nrow(census) == nrow(nbi), all(census$cod_prov == "06"),
          n_distinct(census$cod_partido) == 135)

write.csv(census, "data/processed/census_radios.csv", row.names = FALSE)
cat(sprintf("Radios: %d | Partidos: %d | Households: %s | NBI households: %.1f%% | Population: %s\n",
            nrow(census), n_distinct(census$cod_partido),
            format(sum(census$hog_total), big.mark = ","),
            100 * sum(census$hog_nbi) / sum(census$hog_total),
            format(sum(census$pob_total), big.mark = ",")))
