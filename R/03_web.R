# Build the display layers for the web map: merge habitat fragments, drop
# redundant vertices and transform to WGS 84 (EPSG:4326). Every area on the
# page comes from the unsimplified EPSG:5514 geometries (02_process.R).

library(tidyverse)
library(sf)
library(yaml)
library(here)

source(here("R", "utils_geo.R"))

# Douglas-Peucker tolerance in EPSG:5514 metres, far below map resolution
# (~0.2 m per pixel at the highest zoom): only (nearly) collinear vertices go,
# and the topology-preserving variant never drops a polygon part or hole
simplify_tol_m <- 0.1
# Decimal places of the coordinates written into the page (6 = ~0.1 m);
# page.qmd and R/04_checks.R read it from web_metadata.yml
coord_digits <- 6L

proc_dir <- here("data", "processed")
web_gpkg <- file.path(proc_dir, "web_layers.gpkg")

habitat <- st_read(file.path(proc_dir, "habitat_in_sites.gpkg"), quiet = TRUE)
sites <- st_read(file.path(proc_dir, "sites.gpkg"), quiet = TRUE)

n_vertices <- \(x) nrow(st_coordinates(x))
n_parts <- \(x) lengths(st_geometry(x))

# Simplify each feature's geometry and keep its attributes. st_make_valid() /
# keep_polygons() may split a feature into rows, so they are re-merged by row.
simplify_display <- function(x) {
  x$row_id <- seq_len(nrow(x))
  simple <- x |>
    select(row_id) |>
    st_simplify(preserveTopology = TRUE, dTolerance = simplify_tol_m) |>
    st_make_valid() |>
    keep_polygons() |>
    group_by(row_id) |>
    summarise(.groups = "drop") |>
    st_cast("MULTIPOLYGON", warn = FALSE)

  # Nothing may get lost: same features, valid, every original part still
  # present (parts touching at a point may merge), and the area moves by no
  # more than the boundary length times the tolerance
  parts_kept <- map_lgl(seq_len(nrow(x)), \(i) {
    parts <- st_cast(st_geometry(x)[i], "POLYGON")
    all(lengths(st_intersects(parts, st_geometry(simple)[i])) > 0)
  })
  boundary_m <- as.numeric(st_length(st_boundary(st_geometry(x))))
  stopifnot(
    identical(simple$row_id, x$row_id),
    all(st_is_valid(simple)),
    all(parts_kept),
    all(abs(area_ha(simple) - area_ha(x)) * 1e4 <= boundary_m * simplify_tol_m)
  )
  st_geometry(x) <- st_geometry(simple)
  select(x, -row_id)
}

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
  simplify_display() |>
  st_transform(4326)

# Site outlines: one per site, so both species' outlines coincide
sites_merged <- sites |>
  distinct(site_code, .keep_all = TRUE) |>
  select(site_code)
sites_web <- sites_merged |>
  simplify_display() |>
  st_transform(4326)

# Zoom bounds from the unsimplified outlines
sites_4326 <- st_transform(sites_merged, 4326)
site_bounds <- st_geometry(sites_4326) |>
  map(\(g) as_tibble_row(as.list(st_bbox(g)))) |>
  bind_rows() |>
  mutate(site_code = sites_4326$site_code, .before = 1)

# Upper bound of how far a drawn vertex can lie from the processed geometry:
# simplification tolerance plus half a rounding step (diagonal) at the
# southernmost latitude, where a degree of longitude is longest
lat_min <- st_bbox(sites_4326)[["ymin"]]
m_per_deg <- 111320
rounding_m <- 0.5 * 10^-coord_digits * m_per_deg * sqrt(1 + cos(lat_min * pi / 180)^2)
max_offset_m <- ceiling(10 * (simplify_tol_m + rounding_m)) / 10

st_write(patches_web, web_gpkg, layer = "habitat_web", delete_dsn = TRUE, quiet = TRUE)
st_write(sites_web, web_gpkg, layer = "sites_web", quiet = TRUE)
write_csv(site_bounds, file.path(proc_dir, "site_bounds.csv"))
write_yaml(
  list(
    simplify_tol_m = simplify_tol_m,
    coord_digits = coord_digits,
    max_offset_m = max_offset_m,
    n_patches = nrow(patches_web),
    n_parts = sum(n_parts(patches_web)),
    n_vertices = n_vertices(patches_web),
    n_vertices_unsimplified = n_vertices(patches),
    merge_area_diff_ha = area_diff
  ),
  file.path(proc_dir, "web_metadata.yml")
)

message(sprintf("Patches: %d | vertices: %d of %d | web_layers.gpkg: %.1f MB",
                nrow(patches_web), n_vertices(patches_web), n_vertices(patches),
                file.size(web_gpkg) / 1e6))
