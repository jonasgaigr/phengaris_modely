# Geometry helpers shared by the processing scripts

area_ha <- function(x) units::drop_units(units::set_units(sf::st_area(x), "ha"))

# Keep only polygonal parts (clipping, unions and st_make_valid() can return
# geometry collections, lines or points along shared edges)
keep_polygons <- function(x) {
  x <- x[!sf::st_is_empty(x), ]
  if (nrow(x) == 0) return(x)
  type <- as.character(sf::st_geometry_type(x))
  parts <- list(x[type %in% c("POLYGON", "MULTIPOLYGON"), ])
  if (any(type == "GEOMETRYCOLLECTION")) {
    gc <- x[type == "GEOMETRYCOLLECTION", ]
    parts <- c(parts, list(sf::st_collection_extract(gc, "POLYGON", warn = FALSE)))
  }
  out <- do.call(rbind, parts)
  out <- out[!sf::st_is_empty(out), ]
  sf::st_cast(out, "MULTIPOLYGON", warn = FALSE)
}
