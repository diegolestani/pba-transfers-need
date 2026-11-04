# Do provincial transfers follow need? Buenos Aires municipalities

Work in progress. A spatial look at how the Province of Buenos Aires distributes resources to its 135 municipalities (partidos), compared with where structural deprivation is concentrated at census-tract level (*radio censal*, INDEC's smallest census unit, about 250 households on average in Buenos Aires).

## Data

| Source | Content | Level | File |
|---|---|---|---|
| INDEC, Censo Nacional de Población, Hogares y Viviendas 2022 (REDATAM, base CPV2022, *Lista de áreas*) | Households by Unmet Basic Needs (NBI) status | Census tract | `data/raw/NBI_tot_BA_2022.xlsx` |
| Same | Population in private dwellings, by sex | Census tract | `data/raw/Pop_Total_BA_2022.xlsx` |
| Same | Households by Material Deprivation Index (IPMH) | Census tract | `data/raw/IPMH_BA_2022.xlsx` |
| Province of Buenos Aires open data portal, *Radios censales* (CC BY 4.0) | Census tract boundaries, 2022 | Census tract | `data/raw/radios-censales-2022-shp.zip` |

NBI follows INDEC's definition: a household is NBI if it has at least one of overcrowding (more than three people per room), inadequate housing, no toilet, a child aged 6–12 not attending school, or low subsistence capacity. It is a structural deprivation measure, not income poverty.

IPMH (Índice de Privación Material de los Hogares) classifies households by deprivation of current resources (an income proxy) and of patrimonial resources (housing quality). The share of households with current-resource deprivation (current-only plus convergent) is used as a second, closer-to-income measure of need.

## Code

| Script | Does |
|---|---|
| `R/01_clean_census.R` | Reads the REDATAM exports, restores 9-digit census tract (radio) codes, joins households, population and IPMH, writes `data/processed/census_radios.csv` |

| `R/02_geography.R` | Joins tract boundaries to census data, builds partido aggregates, and decomposes tract-level variation in deprivation into within- and between-partido components |
| `R/03_maps_need.R` | Figure 1 (partido vs. tract-level NBI) and Figure 2 (spread of tract NBI rates within partidos) |

Run the scripts in order from the repository root, e.g. `Rscript R/01_clean_census.R`.

## First results

Most of the variation in deprivation is **within** partidos, not between them. Weighting by households, 83% of the variance in tract NBI rates and 77% for IPMH current-resource deprivation lies within partidos. Any allocation rule that works with partido averages misses most of where need is.

![Partido vs tract-level NBI](output/figures/fig1_nbi_tracts.png)

![Within-partido spread](output/figures/fig2_within_partido_spread.png)

## Requirements

R (≥ 4.3) with `readxl`, `dplyr`, `sf`, `ggplot2`, `patchwork`, `scales`.
