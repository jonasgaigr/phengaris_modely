# Post-render checks for both language versions. Run after render.R:
#   Rscript R/04_checks.R [extra files or folders to scan for credentials, e.g. logs]
# Prints PASS/FAIL per check; never prints credential values.

library(tidyverse)
library(sf)
library(readxl)
library(janitor)
library(xml2)
library(jsonlite)
library(yaml)
library(here)

source(here("R", "utils_geo.R"))

pages <- c(cs = here("index.html"), en = here("index-en.html"))
strings <- read_yaml(here("i18n", "strings.yml"))
results <- new.env()

check <- function(name, ok, detail = "") {
  assign(name, ok, envir = results)
  status <- if (ok) "PASS" else "FAIL"
  suffix <- if (nzchar(detail)) paste0(" – ", detail) else ""
  cat(sprintf("[%s] %s%s\n", status, name, suffix))
}
list_files <- function(path) {
  if (dir.exists(path)) list.files(path, recursive = TRUE, full.names = TRUE) else path
}
collapse_files <- function(files) {
  if (length(files) == 0) "" else paste0(" (", paste(files, collapse = ", "), ")")
}

# --- 1. Credentials never appear in outputs ---------------------------------
# Values are read with Sys.getenv() and only compared; they are never printed.
cred_vars <- c("NDOP_USER", "NDOP_PWD")
cred_values <- discard(Sys.getenv(cred_vars), \(x) !nzchar(x))

scan_paths <- c(
  pages, here("page.qmd"), here("render.R"), here("_quarto.yml"),
  map(c(here("data"), here("R"), here("i18n"), here("assets")), list_files),
  map(commandArgs(trailingOnly = TRUE), list_files)
) |>
  unlist() |>
  unique() |>
  keep(file.exists)

# A value that equals the OS account name also occurs in local file paths
# (e.g. in logs); such hits are reported separately and do not fail the check.
profile <- Sys.getenv("USERPROFILE")
profile_paths <- discard(unique(c(profile, gsub("\\\\", "/", profile))), \(x) !nzchar(x))
count_hits <- function(bytes, value) {
  length(grepRaw(charToRaw(value), bytes, fixed = TRUE, all = TRUE))
}
hits <- map(scan_paths, \(f) {
  bytes <- readBin(f, "raw", file.size(f))
  total <- sum(map_int(cred_values, \(v) count_hits(bytes, v)))
  in_profile <- sum(map_int(cred_values, \(v) {
    in_path <- keep(profile_paths, \(p) grepl(v, p, fixed = TRUE))
    sum(map_int(in_path, \(p) count_hits(bytes, p)))
  }))
  c(total = total, outside_profile = max(total - in_profile, 0))
}) |>
  bind_rows() |>
  mutate(file = basename(scan_paths))

check(
  "no credential values in outputs",
  sum(hits$outside_profile) == 0,
  sprintf(
    "%d variables, %d files; %d hits outside the OS profile path%s; %d inside it%s",
    length(cred_values), nrow(hits),
    sum(hits$outside_profile), collapse_files(hits$file[hits$outside_profile > 0]),
    sum(hits$total - hits$outside_profile), collapse_files(hits$file[hits$total > 0])
  )
)

# --- 2. Dictionary completeness -----------------------------------------------
is_blank <- \(x) is.null(x) || !nzchar(trimws(x))
incomplete <- names(strings)[map_lgl(strings, \(s) is_blank(s$cs) || is_blank(s$en))]
check(
  "every dictionary key has cs and en",
  length(incomplete) == 0,
  paste(length(strings), "keys", collapse_files(incomplete))
)

# --- 3. Language leakage ---------------------------------------------------------
widget_json <- function(doc, id) {
  xpath <- sprintf("//script[@type='application/json'][@data-for='%s']", id)
  fromJSON(xml_text(xml_find_first(doc, xpath)), simplifyVector = FALSE)
}

page_corpus <- function(path) {
  doc <- read_html(path)
  # visible text without code, scripts and styles
  visible <- xml_new_root(xml_find_first(doc, "//body"), .copy = TRUE)
  hidden <- "//script | //style | //pre | //code | //*[contains(@class, 'sourceCode')]"
  xml_remove(xml_find_all(visible, hidden))
  # strings rendered client-side by the widgets (groups, popups, tables, legend)
  widget_strings <- xml_find_all(doc, "//script[@type='application/json'][@data-for]") |>
    map(\(n) unlist(fromJSON(xml_text(n), simplifyVector = FALSE))) |>
    unlist() |>
    keep(is.character) |>
    discard(\(s) str_detect(s, "function\\s*\\(|table\\.on\\(")) |>
    str_replace_all("<[^>]+>", " ")
  list(
    doc = doc,
    text = paste(c(xml_text(visible), widget_strings), collapse = "\n"),
    html_lang = xml_attr(xml_find_first(doc, "//html"), "lang")
  )
}
corpus <- map(pages, page_corpus)

# Does a dictionary value (placeholders as wildcards) occur as whole words?
contains_value <- function(text, value) {
  pattern <- value |>
    str_replace_all("([()\\[\\]+?|^$.])", "\\\\\\1") |>
    str_replace_all("\\\\?\\{[^}]+\\\\?\\}", ".*")
  str_detect(text, regex(paste0("(?<![\\p{L}])", pattern, "(?![\\p{L}])")))
}

# Formatting and link keys are not text
non_text_keys <- c("big_mark", "decimal_mark", "fmt_pct", "lang_switch_href",
                   "lang_switch_hreflang")
for (l in names(pages)) {
  other <- setdiff(names(pages), l)
  leaked <- setdiff(names(strings), non_text_keys) |>
    keep(\(k) !identical(strings[[k]][[l]], strings[[k]][[other]])) |>
    keep(\(k) contains_value(corpus[[l]]$text, strings[[k]][[other]]))
  check(sprintf("no %s dictionary strings on the %s page", other, l),
        length(leaked) == 0, collapse_files(leaked))
  check(sprintf("html lang = %s", l), identical(corpus[[l]]$html_lang, l),
        corpus[[l]]$html_lang)
}

# Heuristics for prose outside the dictionary
site_names <- read_csv(here("data/processed/site_summary.csv"), show_col_types = FALSE)$site_name
allowed_cz <- c(unlist(str_split(site_names, "[^\\p{L}]+")), "Česky", "ČR", "KVES")
cz_letters <- "\\p{L}*[ěščřžýáíéůúťďňóĚŠČŘŽÝÁÍÉŮÚŤĎŇÓ]\\p{L}*"
en_cz_words <- str_extract_all(corpus$en$text, cz_letters)[[1]] |>
  unique() |>
  setdiff(allowed_cz)
check("no Czech words on the en page (outside site names)", length(en_cz_words) == 0,
      paste(head(en_cz_words, 20), collapse = ", "))

en_words <- regex("\\b(the|and|of|with|which|habitat|site|sites|area)\\b")
cs_en_words <- unique(str_extract_all(corpus$cs$text, en_words)[[1]])
check("no common English words on the cs page", length(cs_en_words) == 0,
      paste(cs_en_words, collapse = ", "))

# --- 4. Identical numbers in both versions ------------------------------------------
dt_data <- function(doc, id) widget_json(doc, id)$x$data
num_cols <- function(d) {
  keep(d, \(col) all(map_lgl(col, \(v) is.numeric(v) || is.null(v))))
}
for (id in c("summary-table", "breakdown-table")) {
  a <- dt_data(corpus$cs$doc, id)
  b <- dt_data(corpus$en$doc, id)
  check(
    sprintf("%s: identical numbers and site codes in cs and en", id),
    identical(num_cols(a), num_cols(b)) && identical(a[[1]], b[[1]]),
    sprintf("%d rows, %d numeric columns", length(a[[1]]), length(num_cols(a)))
  )
}

map_geom <- function(doc) {
  widget_json(doc, "overview-map")$x$calls |>
    keep(\(call) call$method == "addPolygons") |>
    map(\(call) call$args[[1]])
}
check("map: identical geometries in cs and en",
      identical(map_geom(corpus$cs$doc), map_geom(corpus$en$doc)))

# --- 5. Area consistency ----------------------------------------------------------------
summary_csv <- read_csv(here("data/processed/site_summary.csv"), show_col_types = FALSE)
habitat <- st_read(here("data/processed/habitat_in_sites.gpkg"), quiet = TRUE)
layer_totals <- habitat |>
  mutate(area_recomputed = area_ha(habitat)) |>
  st_drop_geometry() |>
  group_by(species) |>
  summarise(layer_ha = sum(area_recomputed))
per_species <- summary_csv |>
  group_by(species) |>
  summarise(sum_sites_ha = sum(habitat_ha)) |>
  left_join(layer_totals, by = "species") |>
  mutate(diff_ha = sum_sites_ha - coalesce(layer_ha, 0))
print(per_species)
check("per-site habitat sums match the intersected layer",
      all(abs(per_species$diff_ha) < 1e-6))

dt_summary <- dt_data(corpus$cs$doc, "summary-table")
check("table habitat areas equal site_summary.csv",
      isTRUE(all.equal(sort(unlist(dt_summary[[5]])), sort(summary_csv$habitat_ha))))

# --- 6. Every xlsx site is in the table -----------------------------------------------------
xlsx_sites <- read_excel(here("data/raw/seznam_predmetolokalit_Natura2000_2_2025.xlsx"),
                         sheet = "Předmětolokality") |>
  clean_names() |>
  filter(typ_lokality == "EVL", kod_sdf %in% c("1059", "1061")) |>
  transmute(species = if_else(kod_sdf == "1061", "nausithous", "teleius"),
            site_code = kod_lokality)
table_sites <- tibble(
  site_code = unlist(dt_summary[[1]]),
  species = case_match(unlist(dt_summary[[3]]),
                       strings$sp_nausithous$cs ~ "nausithous",
                       strings$sp_teleius$cs ~ "teleius")
)
missing <- anti_join(xlsx_sites, table_sites, by = c("species", "site_code"))
extra <- anti_join(table_sites, xlsx_sites, by = c("species", "site_code"))
check("every xlsx site x species is in the table (and nothing else)",
      nrow(missing) == 0 && nrow(extra) == 0,
      sprintf("xlsx %d, table %d, missing %d, extra %d", nrow(xlsx_sites),
              nrow(table_sites), nrow(missing), nrow(extra)))

# --- Sizes ------------------------------------------------------------------------------------
cat("\nRendered file sizes:\n")
walk(pages, \(p) cat(sprintf("  %-14s %6.1f MB\n", basename(p), file.size(p) / 1e6)))

if (!all(unlist(as.list(results)))) quit(status = 1)
