# Build lightweight display layers for the web map: merge habitat fragments,
# transform to WGS 84 (EPSG:4326) and simplify. Display only – every area on
# the page comes from the unsimplified EPSG:5514 geometries (02_process.R).

library(tidyverse)
library(sf)
library(rmapshaper)
library(yaml)
library(here)

source(here("R", "utils_geo.R"))

# Share of vertices kept by mapshaper (Visvalingam), display only
keep_habitat <- 0.15
keep_sites <- 0.15

proc_dir <- here("data", "processed")
web_gpkg <- file.path(proc_dir, "web_layers.gpkg")

habitat <- st_read(file.path(proc_dir, "habitat_in_sites.gpkg"), quiet = TRUE)
sites <- st_read(file.path(proc_dir, "sites.gpkg"), quiet = TRUE)

# One merged patch per species x site x KVES category x probability class
patch_keys <- c("species", "site_code", "site_name", "kves", "p_class_lower", "p_class_upper")
patches <- habitat |>
  group_by(across(all_of(patch_keys))) |>
  summarise(n_fragments = n(), .groups = "drop") |>
  st_make_valid() |>
  keep_polygons() |>
  # re-merge groups that st_make_valid() / keep_polygons() split into rows
  group_by(across(all_of(c(patch_keys, "n_fragments")))) |>
  summarise(.groups = "drop") |>
  st_cast("MULTIPOLYGON", warn = FALSE)
patches$area_ha <- area_ha(patches)

# Merging must not change the area (fragments do not overlap)
area_diff <- sum(patches$area_ha) - sum(habitat$area_ha)
stopifnot(abs(area_diff) < 0.01)

patches_web <- patches |>
  st_transform(4326) |>
  ms_simplify(keep = keep_habitat, keep_shapes = TRUE)

# Site outlines: simplify each site once so both species' outlines coincide
sites_web <- sites |>
  distinct(site_code, .keep_all = TRUE) |>
  select(site_code) |>
  st_transform(4326) |>
  ms_simplify(keep = keep_sites, keep_shapes = TRUE)

# Zoom bounds from the unsimplified outlines
sites_4326 <- sites |>
  distinct(site_code, .keep_all = TRUE) |>
  st_transform(4326)
site_bounds <- st_geometry(sites_4326) |>
  map(\(g) as_tibble_row(as.list(st_bbox(g)))) |>
  bind_rows() |>
  mutate(site_code = sites_4326$site_code, .before = 1)

st_write(patches_web, web_gpkg, layer = "habitat_web", delete_dsn = TRUE, quiet = TRUE)
st_write(sites_web, web_gpkg, layer = "sites_web", quiet = TRUE)
write_csv(site_bounds, file.path(proc_dir, "site_bounds.csv"))
write_yaml(
  list(keep_habitat = keep_habitat, keep_sites = keep_sites,
       n_patches = nrow(patches_web), merge_area_diff_ha = area_diff),
  file.path(proc_dir, "web_metadata.yml")
)

message(sprintf("Patches: %d | web_layers.gpkg: %.1f MB", nrow(patches_web),
                file.size(web_gpkg) / 1e6))
