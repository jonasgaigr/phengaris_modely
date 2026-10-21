# Render the Czech (index.html) and English (index-en.html) versions of
# page.qmd. Title, document language and the language switch come from
# i18n/strings.yml through a temporary metadata file, so Quarto's own UI
# strings (table of contents, code folding, dates) are translated too.
#
# Usage: Rscript render.R

library(yaml)
library(htmltools)
library(here)

strings <- read_yaml(here("i18n", "strings.yml"))
outputs <- c(cs = "index.html", en = "index-en.html")
# Publication date style per language, e.g. 21. října 2026 / 21 October 2026
date_formats <- c(cs = "long", en = "D MMMM YYYY")

quarto <- Sys.which("quarto")
if (!nzchar(quarto)) stop("Quarto CLI not found on PATH", call. = FALSE)

for (lang in names(outputs)) {
  tr <- \(key) strings[[key]][[lang]]
  target_lang <- tr("lang_switch_hreflang")
  lang_bar <- div(
    class = "lang-bar",
    a(href = tr("lang_switch_href"), hreflang = target_lang, lang = target_lang,
      tr("lang_switch"))
  )

  meta_file <- tempfile(paste0("meta-", lang, "-"), fileext = ".yml")
  write_yaml(
    list(
      lang = lang,
      title = tr("title"),
      subtitle = tr("subtitle"),
      `date-format` = date_formats[[lang]],
      `include-before-body` = list(list(text = as.character(lang_bar)))
    ),
    meta_file
  )

  message("Rendering ", outputs[[lang]], " (lang = ", lang, ")")
  status <- withr::with_dir(here(), system2(quarto, c(
    "render", "page.qmd",
    "-P", paste0("lang:", lang),
    "--metadata-file", meta_file,
    "-o", outputs[[lang]]
  )))
  unlink(meta_file)
  if (status != 0) stop("quarto render failed for lang = ", lang, call. = FALSE)
}
