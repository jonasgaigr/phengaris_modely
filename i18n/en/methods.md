### Data sources

- **SCI boundaries** – AOPK ČR (Nature Conservation Agency of the Czech Republic), dataset [Sites of Community Importance](`r meta$sources$evl$page`) (ESRI shapefile in S-JTSK), boundaries last changed `r fmt_date(meta$evl_updated)`, downloaded `r fmt_date(meta$sources$evl$downloaded)`. Licence [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), © AOPK ČR.
- **Qualifying features** – AOPK ČR, [list of qualifying features of Natura 2000 sites, version 2/2025](`r meta$sources$features$url`) (xlsx), downloaded `r fmt_date(meta$sources$features$downloaded)`.
- **Modelled habitat** – layers `r paste0("\x60", unlist(meta$sources$habitat), "\x60", collapse = " and ")`: KVES polygons with the modelled probability of occurrence of the species (WGS 84).
- **Basemaps** – © OpenStreetMap contributors; Esri World Imagery.

### Coordinate reference system

All geometry operations and area calculations use S-JTSK / Krovak East North (EPSG:`r meta$crs_work`) on unsimplified geometries. The map on this page uses WGS 84 (EPSG:4326) and simplified geometries, for display only.

### Processing steps

1. Both species were found in the list of qualifying features by their Habitats Directive code (1061 – Dusky Large Blue, 1059 – Scarce Large Blue), cross-checked by Latin name with either genus, *Phengaris* or *Maculinea*. Only rows for SCIs were used; Special Protection Areas (SPAs) are not included. Every site code in the list has a polygon in the SCI layer.
2. SCI and model geometries were repaired with `st_make_valid()`; the model layer was transformed from WGS 84 to S-JTSK.
3. Preferred habitat means polygons with a modelled probability of occurrence p ≥ `r p_min_lab`, regardless of KVES category. The area is further broken down by KVES category and by probability class (`r paste(p_class_labs, collapse = ", ")`). Modelled habitat with a lower probability is given in the summary table for comparison. In the Scarce Large Blue layer, the probability is stored in the field `ver.nausithous.romp`; it holds the Scarce Large Blue model output, only the field name was carried over from the Dusky Large Blue layer.
4. Each species' layer was intersected only with the sites where that species is a qualifying feature.
5. Site area is calculated from the SCI polygon and may differ slightly from the official area in the register. Habitat cover refers to this calculated area.
6. The habitat area summed over sites was checked against the total area of the intersected layer and against the area of its union, so no area is counted twice.
7. For the map, preferred habitat was merged by site, KVES category and probability class, transformed to WGS 84 and simplified with mapshaper (`r tr("fmt_pct", x = fmt_num(100 * web_meta$keep_habitat, 1))` of vertices kept, no polygon dropped). Areas shown in the map and in the tables come from the unsimplified geometries.

### How “within the SCI” is defined

Habitat polygons were clipped to the site boundary (geometric intersection, `st_intersection()`), so only the part of a polygon that lies inside the SCI is counted. Polygons crossing the site boundary are listed in the summary table together with the area that lies outside the site and is not counted. Sites where the model finds no preferred habitat are marked in the column “Flag”.

Processing is documented in the scripts `R/01_download.R`, `R/02_process.R` and `R/03_web.R`; the page is built from the template `page.qmd`.
