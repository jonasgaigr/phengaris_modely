# Translation and formatting helpers for page.qmd. Strings live in
# i18n/strings.yml as `key: {cs: ..., en: ...}`.

i18n_langs <- c("cs", "en")

read_strings <- function(path = here::here("i18n", "strings.yml")) {
  yaml::read_yaml(path)
}

# Returns tr(key, ...) for one language; `...` fills {placeholders}
translator <- function(strings, lang) {
  stopifnot(lang %in% i18n_langs)
  function(key, ...) {
    s <- strings[[key]][[lang]]
    if (is.null(s)) {
      stop(sprintf("Missing string '%s' for language '%s'", key, lang), call. = FALSE)
    }
    if (...length() > 0) s <- glue::glue_data(list(...), s)
    as.character(s)
  }
}

# Number formatter using the language's decimal and thousands marks
number_formatter <- function(tr) {
  function(x, accuracy = 0.1) {
    scales::label_number(
      accuracy = accuracy,
      big.mark = tr("big_mark"),
      decimal.mark = tr("decimal_mark")
    )(x)
  }
}

# Dates: "20. 10. 2026" (cs) or "20 October 2026" (en)
date_formatter <- function(lang) {
  function(x) {
    x <- as.Date(x)
    if (lang == "cs") {
      sprintf("%d. %d. %d", as.integer(format(x, "%d")), as.integer(format(x, "%m")),
              as.integer(format(x, "%Y")))
    } else {
      sprintf("%d %s %s", as.integer(format(x, "%d")), month.name[as.integer(format(x, "%m"))],
              format(x, "%Y"))
    }
  }
}

# Translate KVES category names (the cs value of each kves_* key is the
# original KATEGORIE value in the habitat layers)
kves_translator <- function(strings, lang) {
  keys <- grep("^kves_", names(strings), value = TRUE)
  lookup <- setNames(
    vapply(keys, \(k) strings[[k]][[lang]], character(1)),
    vapply(keys, \(k) strings[[k]][["cs"]], character(1))
  )
  function(x) {
    missing <- setdiff(unique(x), names(lookup))
    if (length(missing) > 0) {
      stop("KVES categories missing in i18n/strings.yml: ", paste(missing, collapse = ", "),
           call. = FALSE)
    }
    unname(lookup[x])
  }
}
