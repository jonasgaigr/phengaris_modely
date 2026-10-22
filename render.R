# Render the Czech (index.html) and English (index-en.html) versions of
# page.qmd. Title, document language, the AOPK ČR header (logo and language
# switch) and footer come from i18n/strings.yml through a temporary metadata
# file, so Quarto's own UI strings (table of contents, code folding, dates)
# are translated too.
#
# Usage: Rscript render.R

library(yaml)
library(htmltools)
library(here)

strings <- read_yaml(here("i18n", "strings.yml"))
sources <- read_yaml(here("data", "processed", "metadata.yml"))$sources
outputs <- c(cs = "index.html", en = "index-en.html")
# Publication date style per language, e.g. 21. října 2026 / 21 October 2026
date_formats <- c(cs = "long", en = "D MMMM YYYY")
# Page sections listed in the footer: anchor = heading key in strings.yml
footer_sections <- c(intro = "sec_intro", methods = "sec_methods", map = "sec_map",
                     table = "sec_table", site = "sec_site", chart = "sec_chart")
aopk_url <- "https://aopk.gov.cz"

quarto <- Sys.which("quarto")
if (!nzchar(quarto)) stop("Quarto CLI not found on PATH", call. = FALSE)

for (lang in names(outputs)) {
  tr <- \(key) strings[[key]][[lang]]
  target_lang <- tr("lang_switch_hreflang")
  logo <- sprintf("assets/logo-%s-white.svg", c(cs = "cz", en = "en")[[lang]])

  # "Header s nadpisem" (WEB manual p. 5): logo on the left on the agency green;
  # the title banner below it is Quarto's title block. Quarto puts
  # include-before-body inside <main>, after the banner, so the script moves the
  # header to the top of the page.
  header <- tagList(
    tags$header(
      class = "aopk-header",
      div(
        class = "aopk-header-inner",
        a(class = "aopk-logo", href = aopk_url, img(src = logo, alt = tr("aopk_name"))),
        a(class = "aopk-lang", href = tr("lang_switch_href"), hreflang = target_lang,
          lang = target_lang, tr("lang_switch"))
      )
    ),
    tags$script(HTML(
      "document.body.prepend(document.currentScript.previousElementSibling);"
    ))
  )

  # Footer (WEB manual p. 6): link columns on the left, AOPK ČR logo on the right
  footer_links <- function(title, hrefs, labels) {
    div(
      class = "aopk-footer-col",
      p(class = "aopk-footer-title", title),
      tags$ul(Map(\(href, label) tags$li(a(href = href, label)), hrefs, labels))
    )
  }
  footer <- tags$footer(
    class = "aopk-footer",
    div(
      class = "aopk-footer-inner",
      footer_links(tr("footer_contents"), paste0("#", names(footer_sections)),
                   vapply(footer_sections, tr, character(1))),
      footer_links(
        tr("footer_sources"),
        c(sources$evl$page, sources$features$url, sources$ndop$page),
        c(tr("src_evl"), tr("src_features"), tr("src_ndop"))
      ),
      a(class = "aopk-footer-logo", href = aopk_url, img(src = logo, alt = tr("aopk_name")))
    ),
    div(
      class = "aopk-footer-bar",
      span(tr("aopk_name")), " | ", a(href = aopk_url, "aopk.gov.cz")
    )
  )

  meta_file <- tempfile(paste0("meta-", lang, "-"), fileext = ".yml")
  write_yaml(
    list(
      lang = lang,
      title = tr("title"),
      subtitle = tr("subtitle"),
      `date-format` = date_formats[[lang]],
      `include-before-body` = list(list(text = as.character(header))),
      `include-after-body` = list(list(text = as.character(footer)))
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
