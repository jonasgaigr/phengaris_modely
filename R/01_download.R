# Download and cache the external inputs into data/raw/ and record their
# provenance (URL, download date, size, MD5 – never credentials) in
# data/raw/SOURCES.md. Files that already exist are not downloaded again.
#
# Note: the EVL download endpoint on data.nature.cz is public (anonymous
# HTTP 200, checked 2026-10-20), so no credentials are sent. If it ever starts
# requiring a login, the request fails with the HTTP status and the script stops.

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

  # Append provenance (no credentials)
  row <- sprintf(
    "| `%s` | <%s> | <%s> | %s | %s | %s | `%s` |",
    src$file, src$url, src$page, src$description,
    format(Sys.Date()), format(file.size(dest), scientific = FALSE),
    unname(tools::md5sum(dest))
  )
  cat(row, "\n", file = sources_md, append = TRUE, sep = "")
  invisible(dest)
}

paths <- vapply(sources, download_cached, character(1))

# Unpack the EVL shapefile (once)
evl_dir <- file.path(raw_dir, "evl")
if (!dir.exists(evl_dir)) {
  unzip(file.path(raw_dir, "evl.zip"), exdir = evl_dir)
  message("Unzipped evl.zip into data/raw/evl/")
}
