# 04_transfers.R
# Provincial transfers to municipalities in 2025: per capita levels, incidence with respect to
# need (concentration curves), and a needs-based counterfactual allocation of the same pool.
# Inputs : data/raw/transferencias-municipios-012010_072026.csv (Buenos Aires open data portal)
#          data/processed/partidos.gpkg (from 02_geography.R)
# Outputs: output/tables/transfers_2025_partido.csv, output/tables/concentration.csv,
#          output/tables/regression_transfers_pc.csv,
#          output/figures/fig3_transfers_vs_need.png, fig4_concentration_curves.png,
#          fig5_counterfactual_map.png
suppressPackageStartupMessages({library(sf); library(dplyr); library(tidyr); library(ggplot2); library(patchwork)})
sf_use_s2(FALSE)
YEAR <- 2025

tr <- read.csv("data/raw/transferencias-municipios-012010_072026.csv",
               colClasses = c(municipio_id = "character"), encoding = "UTF-8")
partidos <- st_read("data/processed/partidos.gpkg", quiet = TRUE)
stopifnot(setequal(unique(tr$municipio_id), partidos$cod_partido))

# Annual totals by partido and concept (current pesos)
grp <- function(x) case_when(
  grepl("^Coparticipaci", x) ~ "copa",          # Coparticipación Bruta (Ley 10.559)
  grepl("Educativo", x)       ~ "educ",          # Fondo de Financiamiento Educativo
  TRUE                        ~ "other")         # other funds and decentralised taxes
annual <- tr |>
  filter(anio == YEAR) |>
  mutate(group = grp(concepto)) |>
  group_by(cod_partido = municipio_id, group) |>
  summarise(monto = sum(monto), .groups = "drop") |>
  pivot_wider(names_from = group, values_from = monto, names_prefix = "tr_") |>
  mutate(tr_total = tr_copa + tr_educ + tr_other)

d <- partidos |>
  left_join(annual, by = "cod_partido") |>
  mutate(tr_pc = tr_total / pob_total,                 # pesos per person (2022 census population)
         copa_pc = tr_copa / pob_total)

# --- Incidence: concentration curves, partidos ranked from most to least deprived ---
# Following fiscal incidence convention (ranking poorest first), a negative concentration
# coefficient means the transfer is concentrated among the most deprived.
conc <- function(df, rank_var, value, weight = "pob_total") {
  df <- df[order(-df[[rank_var]]), ]                  # most deprived first
  w <- df[[weight]] / sum(df[[weight]])
  v <- df[[value]] / sum(df[[value]])
  p <- cumsum(w); L <- cumsum(v)
  coef <- 1 - sum(w * (L + c(0, head(L, -1))))        # 1 - 2 * area under curve (trapezoid)
  list(curve = data.frame(p = c(0, p), L = c(0, L)), coef = coef)
}
dd <- st_drop_geometry(d)
series <- c(tr_total = "All transfers", tr_copa = "Coparticipaci\u00f3n",
            tr_educ = "Education fund", hog_nbi = "Households with NBI (need)")
curves <- list(); coefs <- list()
for (rk in c("nbi_share", "ipmh_corr_share")) for (s in names(series)) {
  r <- conc(dd, rk, s)
  curves[[paste(rk, s)]] <- cbind(r$curve, series = series[[s]], ranking = rk)
  coefs[[paste(rk, s)]] <- data.frame(ranking = rk, series = series[[s]], concentration = r$coef)
}
curves <- bind_rows(curves); coefs <- bind_rows(coefs)
# The population line (the diagonal) has coefficient 0 by construction

# --- Counterfactual: same pool allocated in proportion to households with NBI ---
pool <- sum(dd$tr_total)
d <- d |>
  mutate(cf_need   = pool * hog_nbi / sum(hog_nbi),
         cf_blend  = pool * (0.5 * pob_total / sum(pob_total) + 0.5 * hog_nbi / sum(hog_nbi)),
         gap_need  = cf_need / tr_total - 1,            # >0: would gain under a needs-based rule
         gap_blend = cf_blend / tr_total - 1)

dir.create("output/tables", recursive = TRUE, showWarnings = FALSE)
readr::write_csv(st_drop_geometry(d) |>
            select(cod_partido, partido, gba24, pob_total, hog_total, hog_nbi, nbi_share,
                   ipmh_corr_share, tr_copa, tr_educ, tr_other, tr_total, tr_pc,
                   cf_need, cf_blend, gap_need, gap_blend),
          "output/tables/transfers_2025_partido.csv")
readr::write_csv(coefs, "output/tables/concentration.csv")

# --- Figure 3: transfers per capita vs need ---
dd <- st_drop_geometry(d)
lab <- dd |> filter(pob_total > 500000 | tr_pc > quantile(tr_pc, 0.97))
fig3 <- ggplot(dd, aes(nbi_share, tr_pc / 1000)) +
  geom_point(aes(size = pob_total, colour = gba24), alpha = 0.75) +
  geom_text(data = lab, aes(label = partido), size = 2.6, vjust = -1.1, colour = "grey25") +
  scale_x_continuous(labels = scales::percent) +
  scale_y_log10(labels = scales::label_comma()) +
  scale_size_area(max_size = 12, guide = "none") +
  scale_colour_manual(values = c(`TRUE` = "#c94a3a", `FALSE` = "#3d5a8a"),
                      labels = c(`TRUE` = "Greater Buenos Aires", `FALSE` = "Rest of province"), name = NULL) +
  labs(title = "Transfers per person track municipal size, not deprivation",
       subtitle = sprintf("Provincial transfers to municipalities, %d, thousand pesos per person (log scale). Point size: population.", YEAR),
       x = "Households with NBI (Censo 2022)", y = "Thousand pesos per person",
       caption = "Source: Buenos Aires Ministry of Economy (transfers); INDEC, Censo 2022 (NBI, population).") +
  theme_minimal(base_size = 10) +
  theme(legend.position = "top", plot.title = element_text(face = "bold", size = 12), plot.title.position = "plot")
ggsave("output/figures/fig3_transfers_vs_need.png", fig3, width = 8, height = 6, dpi = 200, bg = "white")

# --- Figure 4: concentration curves (NBI ranking) ---
cn <- filter(coefs, ranking == "nbi_share")
cv <- filter(curves, ranking == "nbi_share") |>
  left_join(cn, by = c("series", "ranking")) |>
  mutate(series = sprintf("%s (CC = %.2f)", series, concentration))
fig4 <- ggplot(cv, aes(p, L, colour = series)) +
  geom_abline(linetype = "dashed", colour = "grey60") +
  geom_line(linewidth = 0.9) +
  scale_x_continuous(labels = scales::percent) + scale_y_continuous(labels = scales::percent) +
  scale_colour_manual(values = c("#7a1c2e", "#3d5a8a", "#8aa6c8", "#e0a040"), name = NULL) +
  coord_equal() +
  labs(title = "Need is concentrated in the most deprived partidos; transfers are not",
       subtitle = "Partidos ranked from most to least deprived (share of households with NBI).\nDashed line: equal per capita allocation. CC: concentration coefficient\n(negative = concentrated among the most deprived; positive = among the least deprived).",
       x = "Cumulative share of population", y = "Cumulative share of the series",
       caption = sprintf("Transfers in %d. Source: Buenos Aires Ministry of Economy; INDEC, Censo 2022.", YEAR)) +
  theme_minimal(base_size = 10) +
  theme(legend.position = c(0.68, 0.18), legend.background = element_rect(fill = "white", colour = NA),
        plot.title = element_text(face = "bold", size = 12), plot.title.position = "plot")
ggsave("output/figures/fig4_concentration_curves.png", fig4, width = 7.5, height = 7.5, dpi = 200, bg = "white")

# --- Figure 5: counterfactual gains and losses ---
brk <- c(-Inf, -0.5, -0.2, 0.2, 0.5, Inf)
lbl <- c("Lose more than 50%", "Lose 20-50%", "Within \u00b120%", "Gain 20-50%", "Gain more than 50%")
pal <- setNames(c("#3d5a8a", "#8aa6c8", "#f2efe9", "#ec8a5b", "#7a1c2e"), lbl)
d <- d |> mutate(gap_class = cut(gap_blend, brk, lbl))
mp <- function(x, sub) ggplot(x) + geom_sf(aes(fill = gap_class), colour = "grey30", linewidth = 0.15) +
  scale_fill_manual(values = pal, drop = FALSE, name = NULL) + labs(subtitle = sub) + theme_void(base_size = 10)
fig5 <- (mp(d, "Buenos Aires province") | mp(filter(d, gba24), "Greater Buenos Aires")) +
  plot_layout(guides = "collect") +
  plot_annotation(
    title = "Who would gain under an allocation that gives half weight to need",
    subtitle = sprintf("Change vs. actual %d transfers if the same pool were split 50%% by population and 50%% by households with NBI.", YEAR),
    caption = "Illustrative, not a policy proposal: a static reallocation that ignores service costs, own revenue capacity and behavioural responses.\nSource: Buenos Aires Ministry of Economy; INDEC, Censo 2022.") &
  theme(legend.position = "bottom", plot.title = element_text(face = "bold", size = 12))
ggsave("output/figures/fig5_counterfactual_map.png", fig5, width = 11, height = 6.5, dpi = 200, bg = "white")

# --- Is need associated with transfers once municipal size is accounted for? ---
# log(transfers per capita) on NBI share, with and without log population.
dd$log_tr_pc <- log(dd$tr_pc); dd$log_pop <- log(dd$pob_total)
mods <- list(need_only = lm(log_tr_pc ~ nbi_share, dd),
             need_size = lm(log_tr_pc ~ nbi_share + log_pop, dd),
             need_size_gba = lm(log_tr_pc ~ nbi_share + log_pop + gba24, dd))
reg <- bind_rows(lapply(names(mods), function(n) {
  co <- summary(mods[[n]])$coefficients
  data.frame(model = n, term = rownames(co), estimate = co[, 1], std_error = co[, 2],
             p_value = co[, 4], r2 = summary(mods[[n]])$r.squared, n = nobs(mods[[n]]))
}))
readr::write_csv(reg, "output/tables/regression_transfers_pc.csv")

# Summary
gba <- dd |> group_by(gba24) |> summarise(pc = sum(tr_total) / sum(pob_total), nbi = sum(hog_nbi) / sum(hog_total))
cat(sprintf("Pool %d: %.0f billion pesos | per capita GBA %.0f vs rest %.0f | NBI GBA %.1f%% vs rest %.1f%%\n",
            YEAR, pool / 1e9, gba$pc[gba$gba24], gba$pc[!gba$gba24], 100 * gba$nbi[gba$gba24], 100 * gba$nbi[!gba$gba24]))
print(coefs, digits = 2)
cat(sprintf("Partidos that would gain >20%% (blend): %d; lose >20%%: %d\n",
            sum(dd$gap_blend > 0.2), sum(dd$gap_blend < -0.2)))
