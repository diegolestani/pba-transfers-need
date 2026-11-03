# Do provincial transfers follow need? Buenos Aires municipalities

Work in progress. A spatial look at how the Province of Buenos Aires distributes resources to its 135 municipalities (partidos), compared with where structural deprivation is concentrated at census-radio level.

## Data

| Source | Content | Level | File |
|---|---|---|---|
| INDEC, Censo Nacional de Población, Hogares y Viviendas 2022 (REDATAM, base CPV2022, *Lista de áreas*) | Households by Unmet Basic Needs (NBI) status | Census radio | `data/raw/NBI_tot_BA_2022.xlsx` |
| Same | Population in private dwellings, by sex | Census radio | `data/raw/Pop_Total_BA_2022.xlsx` |

NBI follows INDEC's definition: a household is NBI if it has at least one of overcrowding (more than three people per room), inadequate housing, no toilet, a child aged 6–12 not attending school, or low subsistence capacity. It is a structural deprivation measure, not income poverty.

## Code

| Script | Does |
|---|---|
| `R/01_clean_census.R` | Reads the REDATAM exports, restores 9-digit radio codes, joins households and population, writes `data/processed/census_radios.csv` |

Run from the repository root with `Rscript R/01_clean_census.R`.

## Requirements

R (≥ 4.3) with `readxl`, `dplyr`.
