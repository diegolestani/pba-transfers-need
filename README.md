# Do provincial transfers follow need? Buenos Aires municipalities

Work in progress. A spatial look at how the Province of Buenos Aires distributes resources to its 135 municipalities (partidos), compared with where structural deprivation is concentrated at census-tract level (*radio censal*, INDEC's smallest census unit, about 250 households on average in Buenos Aires).

## Data

| Source | Content | Level | File |
|---|---|---|---|
| INDEC, Censo Nacional de Población, Hogares y Viviendas 2022 (REDATAM, base CPV2022, *Lista de áreas*) | Households by Unmet Basic Needs (NBI) status | Census tract | `data/raw/NBI_tot_BA_2022.xlsx` |
| Same | Population in private dwellings, by sex | Census tract | `data/raw/Pop_Total_BA_2022.xlsx` |
| Same | Households by Material Deprivation Index (IPMH) | Census tract | `data/raw/IPMH_BA_2022.xlsx` |
| Province of Buenos Aires open data portal, *Radios censales* (CC BY 4.0) | Census tract boundaries, 2022 | Census tract | `data/raw/radios-censales-2022-shp.zip` |
| Province of Buenos Aires open data portal, *Transferencias a municipios* (CC BY 4.0), Ministry of Economy | Monthly transfers to municipalities by concept, Jan 2010 – Jul 2026 | Partido | `data/raw/transferencias-municipios-012010_072026.csv` |

NBI follows INDEC's definition: a household is NBI if it has at least one of overcrowding (more than three people per room), inadequate housing, no toilet, a child aged 6–12 not attending school, or low subsistence capacity. It is a structural deprivation measure, not income poverty.

IPMH (Índice de Privación Material de los Hogares) classifies households by deprivation of current resources (an income proxy) and of patrimonial resources (housing quality). The share of households with current-resource deprivation (current-only plus convergent) is used as a second, closer-to-income measure of need.

## Code

| Script | Does |
|---|---|
| `R/01_clean_census.R` | Reads the REDATAM exports, restores 9-digit census tract (radio) codes, joins households, population and IPMH, writes `data/processed/census_radios.csv` |

| `R/02_geography.R` | Joins tract boundaries to census data, builds partido aggregates, and decomposes tract-level variation in deprivation into within- and between-partido components |
| `R/03_maps_need.R` | Figure 1 (partido vs. tract-level NBI) and Figure 2 (spread of tract NBI rates within partidos) |
| `R/04_transfers.R` | 2025 transfers per capita by partido, concentration curves with respect to need, size-controlled regression, and a needs-based counterfactual allocation (Figures 3–5) |

Run the scripts in order from the repository root, e.g. `Rscript R/01_clean_census.R`.

## First results

Most of the variation in deprivation is **within** partidos, not between them. Weighting by households, 83% of the variance in tract NBI rates and 77% for IPMH current-resource deprivation lies within partidos. Any allocation rule that works with partido averages misses most of where need is.

![Partido vs tract-level NBI](output/figures/fig1_nbi_tracts.png)

![Within-partido spread](output/figures/fig2_within_partido_spread.png)

### Transfers and need

In 2025 the province transferred about 4.35 trillion pesos to municipalities; coparticipación (Ley 10.559) was 77% of it.

- **Transfers are not concentrated where need is.** Ranking partidos from most to least deprived, households with NBI have a concentration coefficient of −0.18, while transfers have +0.11 (coparticipación +0.12). Greater Buenos Aires receives about 190,000 pesos per person against 348,000 in the rest of the province, despite a higher NBI rate (7.0% vs 5.4%). The pattern holds, more weakly, when need is measured with IPMH current-resource deprivation (+0.05).
- **Size, not need, explains per capita transfers.** A 1% larger population is associated with about 0.4% lower transfers per person, and size alone explains most of the variation (R² rises from 0.20 to 0.75 when it is added). Once size is controlled for, the association with NBI is small and not significant at 5%. Transfers do not respond to need in either direction; they follow scale.
- **Reallocating with half weight on need would shift resources sharply.** Splitting the same pool 50% by population and 50% by NBI households would raise transfers by more than 20% in 24 partidos, mostly in Greater Buenos Aires, and cut them by more than 20% in 92. This is an illustration of how far current allocation is from need, not a proposal: it ignores the fixed costs of small municipalities, the services (notably hospitals) that the current formula rewards, and own revenue capacity.

![Transfers vs need](output/figures/fig3_transfers_vs_need.png)

![Concentration curves](output/figures/fig4_concentration_curves.png)

![Counterfactual](output/figures/fig5_counterfactual_map.png)

## Requirements

R (≥ 4.3) with `readxl`, `dplyr`, `tidyr`, `sf`, `ggplot2`, `patchwork`, `scales`.
