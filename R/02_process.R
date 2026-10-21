# Intersect the modelled habitat of Phengaris nausithous and P. teleius with the
# EVL (SCI) sites where each species is a qualifying feature, and compute
# per-site areas. All geometry operations run in S-JTSK / Krovak East North
# (EPSG:5514) on unsimplified geometries. Outputs go to data/processed/.

library(tidyverse)
library(sf)
library(readxl)
library(janitor)
library(yaml)
library(here)

source(here("R", "utils_geo.R"))

crs_work <- 5514

# Preferred habitat = modelled polygons with probability >= p_min, all KVES
# categories (decision of 2026-10-20). Areas are broken down by KVES category
# and by probability class.
p_min <- 0.7
p_breaks <- c(0.7, 0.8, 0.9, 1)

species <- tribble(
  ~species,     ~sdf_code, ~gpkg,
  "nausithous", "1061",    "nausithous_modelled_KVES.gpkg",
  "teleius",    "1059",    "teleius_modelled_KVES.gpkg"
)

# The probability field is called "ver.nausithous.romp" in both layers; in the
# teleius layer it holds the teleius model output (confirmed 2026-10-20)
prob_field <- "ver.nausithous.romp"

# Polygons whose area outside the site exceeds this are counted as straddling
# the boundary (ignores numerical noise from clipping), in ha (= 1 m2)
straddle_tol_ha <- 1e-4

raw_dir <- here("data", "raw")
out_dir <- here("data", "processed")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# --- Site x feature list --------------------------------------------------------

features <- read_excel(
  file.path(raw_dir, "seznam_predmetolokalit_Natura2000_2_2025.xlsx"),
  sheet = "Předmětolokality"
) |>
  clean_names()

# Match by Habitats Directive code or by name with either genus
species_rows <- features |>
  mutate(
    code = str_trim(kod_sdf),
    lat = str_squish(str_to_lower(nazev_latinsky_druh)),
    species = case_when(
      code == "1061" | str_detect(lat, "^(phengaris|maculinea) nausithous") ~ "nausithous",
      code == "1059" | str_detect(lat, "^(phengaris|maculinea) teleius") ~ "teleius"
    )
  ) |>
  filter(!is.na(species), typ_lokality == "EVL")

dups <- count(species_rows, species, kod_lokality) |> filter(n > 1)
if (nrow(dups) > 0) {
  stop("Unexpected duplicate site x species rows in the xlsx:\n",
       paste(capture.output(print(dups)), collapse = "\n"), call. = FALSE)
}

species_sites <- species_rows |>
  select(species, site_code = kod_lokality)

# --- EVL sites ------------------------------------------------------------------

evl_raw <- st_read(file.path(raw_dir, "evl", "evl.shp"), quiet = TRUE)
stopifnot(all(evl_raw$KAT == "EVL"))
evl_updated <- max(as.Date(as.character(c(evl_raw$ZMENA_G, evl_raw$ZMENA_T)), "%Y%m%d"))

evl <- evl_raw |>
  st_transform(crs_work) |>
  st_make_valid() |>
  keep_polygons() |>
  select(site_code = SITECODE, site_name = NAZEV, site_area_official_ha = ROZL)

missing_sites <- anti_join(species_sites, st_drop_geometry(evl), by = "site_code")
if (nrow(missing_sites) > 0) {
  stop("Site codes from the xlsx missing in the EVL layer: ",
       paste(missing_sites$site_code, collapse = ", "), call. = FALSE)
}

sites <- evl |>
  inner_join(species_sites, by = "site_code", relationship = "one-to-many") |>
  mutate(site_area_ha = area_ha(geometry)) |>
  relocate(species) |>
  arrange(species, site_code)

# Sites of one species must not overlap, otherwise habitat would be counted twice
site_overlap_ha <- sites |>
  group_by(species) |>
  group_map(\(x, key) sum(x$site_area_ha) - area_ha(st_union(x))) |>
  set_names(sort(unique(sites$species))) |>
  map_dbl(identity)
if (any(abs(site_overlap_ha) > 0.01)) {
  stop("Sites of the same species overlap (ha): ",
       paste(names(site_overlap_ha), round(site_overlap_ha, 3), collapse = "; "), call. = FALSE)
}

# --- Habitat inside sites -------------------------------------------------------

# Read habitat polygons around one site. The habitat layers are in WGS 84, so
# the site's bbox is taken in WGS 84 and padded by ~150 m; the GeoPackage
# spatial index makes this fast. Exact selection happens in EPSG:5514 below.
read_candidates <- function(gpkg, site) {
  bb <- st_bbox(st_transform(site, 4326))
  pad <- 0.002
  bb_pad <- st_bbox(c(xmin = bb[["xmin"]] - pad, ymin = bb[["ymin"]] - pad,
                      xmax = bb[["xmax"]] + pad, ymax = bb[["ymax"]] + pad), crs = st_crs(4326))
  st_read(here(gpkg), quiet = TRUE, fid_column_name = "hab_fid",
          wkt_filter = st_as_text(st_as_sfc(bb_pad)))
}

process_site <- function(site, gpkg) {
  site_geom <- st_geometry(site)

  cand <- read_candidates(gpkg, site) |>
    select(hab_fid, kves = KATEGORIE, p = all_of(prob_field)) |>
    st_transform(crs_work) |>
    st_make_valid() |>
    keep_polygons()
  cand <- cand[lengths(st_intersects(cand, site_geom)) > 0, ]
  cand$poly_area_ha <- area_ha(cand)
  # attributes describe the whole polygon, so they hold for its clipped parts
  st_agr(cand) <- "constant"

  if (nrow(cand) > 0) {
    clipped <- st_intersection(cand, site_geom) |> keep_polygons()
  } else {
    clipped <- cand
  }
  clipped$area_ha <- area_ha(clipped)

  pref <- clipped |> filter(p >= p_min)

  # Straddling = preferred polygons partly outside the site
  straddle <- pref |>
    st_drop_geometry() |>
    group_by(hab_fid, poly_area_ha) |>
    summarise(inside_ha = sum(area_ha), .groups = "drop") |>
    mutate(outside_ha = poly_area_ha - inside_ha) |>
    filter(outside_ha > straddle_tol_ha)

  summary <- tibble(
    habitat_ha = sum(pref$area_ha),
    n_fragments = nrow(pref),
    below_threshold_ha = sum(clipped$area_ha[clipped$p < p_min]),
    n_straddling = nrow(straddle),
    straddling_total_ha = sum(straddle$poly_area_ha),
    cut_off_ha = sum(straddle$outside_ha)
  )

  pref <- pref |>
    mutate(
      species = site$species,
      site_code = site$site_code,
      site_name = site$site_name,
      p_class = findInterval(p, p_breaks, rightmost.closed = TRUE),
      p_class_lower = p_breaks[p_class],
      p_class_upper = p_breaks[p_class + 1]
    ) |>
    select(species, site_code, site_name, hab_fid, kves, p, p_class_lower, p_class_upper, area_ha)

  list(summary = summary, habitat = pref)
}

results <- map(seq_len(nrow(sites)), \(i) {
  site <- sites[i, ]
  gpkg <- species$gpkg[species$species == site$species]
  message(sprintf("[%2d/%d] %-10s %s %s", i, nrow(sites), site$species,
                  site$site_code, site$site_name))
  process_site(site, gpkg)
})

habitat <- map(results, "habitat") |>
  bind_rows() |>
  st_as_sf() |>
  st_cast("MULTIPOLYGON", warn = FALSE)
stopifnot(st_crs(habitat) == st_crs(crs_work))

site_summary <- sites |>
  st_drop_geometry() |>
  bind_cols(bind_rows(map(results, "summary"))) |>
  mutate(
    cover_pct = 100 * habitat_ha / site_area_ha,
    flag_zero_habitat = habitat_ha == 0
  ) |>
  relocate(cover_pct, .after = habitat_ha)

breakdown <- habitat |>
  st_drop_geometry() |>
  group_by(species, site_code, site_name, kves, p_class_lower, p_class_upper) |>
  summarise(area_ha = sum(area_ha), n_fragments = n(), .groups = "drop") |>
  left_join(select(site_summary, species, site_code, habitat_ha), by = c("species", "site_code")) |>
  mutate(share_of_site_habitat_pct = 100 * area_ha / habitat_ha) |>
  select(-habitat_ha) |>
  arrange(species, site_code, kves, p_class_lower)

# --- Checks ---------------------------------------------------------------------

stopifnot(
  # every site from the xlsx is in the summary, once
  nrow(site_summary) == nrow(species_sites),
  nrow(anti_join(species_sites, site_summary, by = c("species", "site_code"))) == 0,
  # per-site sums match the intersected layer
  isTRUE(all.equal(
    site_summary |> group_by(species) |> summarise(a = sum(habitat_ha)) |> pull(a),
    habitat |> st_drop_geometry() |> group_by(species) |> summarise(a = sum(area_ha)) |> pull(a)
  )),
  isTRUE(all.equal(sum(breakdown$area_ha), sum(site_summary$habitat_ha)))
)

# No double counting: summed fragment area equals the area of their union
union_check <- habitat |>
  group_by(species) |>
  group_map(\(x, key) {
    tibble(
      species = key$species,
      sum_fragments_ha = sum(x$area_ha),
      union_ha = area_ha(st_union(x))
    )
  }) |>
  bind_rows() |>
  mutate(diff_ha = sum_fragments_ha - union_ha)
print(union_check)
if (any(abs(union_check$diff_ha) > 0.01)) {
  stop("Habitat fragments overlap: summed area differs from union area", call. = FALSE)
}

# --- Outputs --------------------------------------------------------------------

st_write(habitat, file.path(out_dir, "habitat_in_sites.gpkg"), layer = "habitat_in_sites",
         delete_dsn = TRUE, quiet = TRUE)
st_write(sites |> left_join(select(site_summary, -site_name, -site_area_ha, -site_area_official_ha),
                            by = c("species", "site_code")),
         file.path(out_dir, "sites.gpkg"), layer = "sites", delete_dsn = TRUE, quiet = TRUE)
write_csv(site_summary, file.path(out_dir, "site_summary.csv"))
write_csv(breakdown, file.path(out_dir, "habitat_breakdown.csv"))

# Provenance for the page (download dates come from data/raw/SOURCES.md)
sources_tbl <- read_lines(file.path(raw_dir, "SOURCES.md")) |>
  str_subset("^\\| `") |>
  str_split_fixed("\\|", 9) |>
  as_tibble(.name_repair = "minimal") |>
  set_names(c("x", "file", "url", "page", "description", "downloaded", "size", "md5", "y")) |>
  mutate(across(everything(), \(x) str_trim(str_remove_all(x, "[`<>]"))))
src <- \(f) as.list(filter(sources_tbl, file == f) |> select(file, url, page, downloaded))

metadata <- list(
  processed = format(Sys.Date()),
  crs_work = crs_work,
  p_min = p_min,
  p_breaks = p_breaks,
  straddle_tol_ha = straddle_tol_ha,
  evl_updated = format(evl_updated),
  sources = list(
    evl = src("evl.zip"),
    features = src("seznam_predmetolokalit_Natura2000_2_2025.xlsx"),
    habitat = as.list(set_names(species$gpkg, species$species))
  ),
  n_sites = as.list(table(site_summary$species)),
  habitat_total_ha = as.list(tapply(site_summary$habitat_ha, site_summary$species, sum)),
  union_check_diff_ha = as.list(set_names(union_check$diff_ha, union_check$species))
)
write_yaml(metadata, file.path(out_dir, "metadata.yml"))

totals <- unlist(metadata$habitat_total_ha)
message("Done. Habitat inside sites (ha): ",
        paste(names(totals), round(totals, 1), collapse = ", "))
