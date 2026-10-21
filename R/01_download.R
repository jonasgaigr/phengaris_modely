# Download and cache the external inputs into data/raw/ and record their
# provenance (URL, download date, size, MD5 – never credentials) in
# data/raw/SOURCES.md. Files that already exist are not downloaded again.
#
# Note: the EVL download endpoint on data.nature.cz is public (anonymous
# HTTP 200, checked 2026-10-20), so no credentials are sent. If it ever starts
# requiring a login, the request fails with the HTTP status and the script stops.
# Only the NDOP export (end of the script) logs in.

library(httr2)
library(here)

raw_dir <- here("data", "raw")
dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
sources_md <- file.path(raw_dir, "SOURCES.md")

sources <- list(
  list(
    file = "evl.zip",
    url = "https://data.nature.cz/ds/8/download",
    page = "https://data.nature.cz/ds/8",
    description = paste("Natura 2000 – evropsky významné lokality (EVL / SCI),",
                        "ESRI shapefile, S-JTSK; © AOPK ČR, CC BY 4.0")
  ),
  list(
    file = "seznam_predmetolokalit_Natura2000_2_2025.xlsx",
    url = paste0("https://webgis.nature.cz/publicdocs/opendata/natura2000/",
                 "seznam_predmetolokalit_Natura2000_2_2025.xlsx"),
    page = "https://data.nature.cz/ds/8",
    description = paste("Seznam předmětů ochrany lokalit Natura 2000",
                        "(site × feature list), stav 2/2025; © AOPK ČR")
  )
)

# Write the SOURCES.md header once
if (!file.exists(sources_md)) {
  writeLines(
    c(
      "# Sources of raw data",
      "",
      "Files in this folder are downloaded by `R/01_download.R` and must not be edited.",
      "",
      "| File | Source URL | Dataset page | Description | Downloaded | Size (bytes) | MD5 |",
      "|---|---|---|---|---|---|---|"
    ),
    sources_md
  )
}

# Append provenance (no credentials)
record_source <- function(src, dest) {
  row <- sprintf(
    "| `%s` | <%s> | <%s> | %s | %s | %s | `%s` |",
    src$file, src$url, src$page, src$description,
    format(Sys.Date()), format(file.size(dest), scientific = FALSE),
    unname(tools::md5sum(dest))
  )
  cat(row, "\n", file = sources_md, append = TRUE, sep = "")
}

download_cached <- function(src) {
  dest <- file.path(raw_dir, src$file)
  if (file.exists(dest)) {
    message("Cached, skipping download: ", src$file)
    return(invisible(dest))
  }

  resp <- request(src$url) |>
    req_user_agent("AOPK CR Natura 2000 Phengaris habitat page (R/httr2)") |>
    req_timeout(300) |>
    req_retry(max_tries = 3) |>
    req_error(is_error = \(resp) FALSE) |>
    req_perform()

  status <- resp_status(resp)
  if (status != 200) {
    # Report the status and the start of the body; no credentials are involved
    body <- tryCatch(substr(resp_body_string(resp), 1, 500), error = \(e) "<binary body>")
    stop(sprintf("Download of %s failed: HTTP %d %s\n%s",
                 src$url, status, resp_status_desc(resp), body), call. = FALSE)
  }

  writeBin(resp_body_raw(resp), dest)
  message("Downloaded: ", src$file)
  record_source(src, dest)
  invisible(dest)
}

paths <- vapply(sources, download_cached, character(1))

# Unpack the EVL shapefile (once)
evl_dir <- file.path(raw_dir, "evl")
if (!dir.exists(evl_dir)) {
  unzip(file.path(raw_dir, "evl.zip"), exdir = evl_dir)
  message("Unzipped evl.zip into data/raw/evl/")
}

# --- NDOP occurrence records -------------------------------------------------------
# Records of both species since ndop_date_from, exported from the Species
# Occurrence Database of AOPK ČR (NDOP) with the rndop package. NDOP requires a
# login: NDOP_USER / NDOP_PWD are read from the user-level .Renviron and are
# only sent to login.nature.cz. The export is kept unfiltered (negative and
# unvalidated records included); 02_process.R selects the records.
# The file holds observer names, so it is not committed (.gitignore).

ndop_date_from <- as.Date("2019-01-01")
ndop_src <- list(
  file = "ndop_phengaris.csv",
  url = "https://portal23.nature.cz/nd/",
  page = "https://portal.nature.cz/nd/",
  description = paste0(
    "NDOP AOPK ČR – records of Phengaris nausithous and P. teleius from ",
    format(ndop_date_from), ", all columns, export via R package rndop ",
    "(login required); © AOPK ČR, CC BY-SA 4.0"
  )
)

# rndop::isop_login() deletes the NDOP_* lines from ~/.Renviron when a login
# fails, so log in here and hand rndop the session cookie (it looks for
# `isop_loginhash` in the global environment). Credentials are never printed.
ndop_login <- function() {
  user <- Sys.getenv("NDOP_USER")
  pwd <- Sys.getenv("NDOP_PWD")
  if (!nzchar(user) || !nzchar(pwd)) {
    stop("NDOP_USER / NDOP_PWD are not set (user-level .Renviron)", call. = FALSE)
  }
  # NDOP binds the session to the user agent, so log in with rndop's own one
  resp <- httr::POST(
    "https://login.nature.cz/login.php?appid=59",
    body = list(isop_user = user, isop_password = pwd, isop_login = "+Přihlásit+se+"),
    httr::user_agent(rndop:::USER_AGENT)
  )
  cookies <- httr::cookies(resp)
  hash <- cookies$value[cookies$name == "isop_loginhash"]
  if (length(hash) != 1 || is.na(hash) || !nzchar(hash)) {
    stop("NDOP login failed (HTTP ", httr::status_code(resp), "); check NDOP_USER / NDOP_PWD",
         call. = FALSE)
  }
  assign("isop_loginhash", hash, envir = globalenv())
}

ndop_dest <- file.path(raw_dir, ndop_src$file)
if (file.exists(ndop_dest)) {
  message("Cached, skipping download: ", ndop_src$file)
} else {
  ndop_login()
  ndop <- lapply(c("Phengaris nausithous", "Phengaris teleius"), \(taxon) {
    payload <- rndop::set_search_payload(
      rfTaxon = taxon,
      rfDatumOd = format(ndop_date_from, "%d.%m.%Y")
    )
    records <- rndop::ndop_download(search_payload = payload)
    if (!is.data.frame(records) || nrow(records) == 0 || !all(records$DRUH == taxon)) {
      stop("NDOP download for ", taxon, " returned no or unexpected records", call. = FALSE)
    }
    records
  })
  readr::write_csv(do.call(rbind, ndop), ndop_dest, na = "")
  message("Downloaded: ", ndop_src$file)
  record_source(ndop_src, ndop_dest)
}
