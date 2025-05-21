##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Scrape DE bill text
## Date: May 2025
## Author: Joe Loffredo (modified)
##################################################

rm(list = ls())
gc()

library(tidyverse)
library(furrr)
library(rvest)
library(glue)
library(fs)

plan(multisession, workers = 11)

# Functions
build_url <- function(bill_id) {
  glue("https://legis.delaware.gov/BillDetail?LegislationId={bill_id}")
}

clean_html <- function(html_content) {
  html_content <- str_remove_all(html_content, "<!--\\[if[^\\]]*\\]>[\\s\\S]*?<!\\[endif\\]-->")
  # Remove Office/Word VML and Smart Tags (v:, o:, w:, etc.)
  html_content <- str_remove_all(html_content, "<v:[^>]+>[\\s\\S]*?</v:[^>]+>")
  html_content <- str_remove_all(html_content, "<o:[^>]+>[\\s\\S]*?</o:[^>]+>")
  html_content <- str_remove_all(html_content, "<w:[^>]+>[\\s\\S]*?</w:[^>]+>")
  html_content <- str_remove_all(html_content, "<v:[^>]+\\s*/>")
  html_content <- str_remove_all(html_content, "<o:[^>]+\\s*/>")
  html_content <- str_remove_all(html_content, "<w:[^>]+\\s*/>")
  # Remove smart tag wrappers but keep inner text
  html_content <- str_remove_all(html_content, "<(state|place|placename|placetype|city|county|country)[^>]*>")
  html_content <- str_remove_all(html_content, "</(state|place|placename|placetype|city|county|country)>")
  
  html_content <- str_remove_all(html_content, "<wrapblock[\\s\\S]*?</wrapblock>")
  html_content <- str_replace_all(html_content, "<p[^>]*>", " ")
  html_content <- str_replace_all(html_content, "</p>", " ")
  html_content <- str_replace_all(html_content, "<div[^>]*>", " ")
  html_content <- str_replace_all(html_content, "</div>", " ")
  html_content <- str_replace_all(html_content, "<a[^>]*>", " ")
  html_content <- str_replace_all(html_content, "</a>", " ")
  html_content <- str_replace_all(html_content, '<u>', '<u class="amendmentInsertedText">')
  html_content <- str_replace_all(html_content, '<s>', '<strike class="amendmentDeletedText">')
  html_content <- str_replace_all(html_content, '</s>', '</strike>')
  html_content <- str_replace_all(
    html_content,
    "\\[([A-Z\\s]+?)\\]",
    '<strike class="amendmentDeletedText">\\1</strike>'
  )
  html_content <- str_replace_all(html_content, "<span[^>]*>", " ")
  html_content <- str_replace_all(html_content, "</span>", " ")
  html_content <- str_replace_all(html_content, "<b[^>]*>", " ")
  html_content <- str_replace_all(html_content, "</b>", " ")
  html_content <- str_replace_all(html_content, "<i[^>]*>", " ")
  html_content <- str_replace_all(html_content, "</i>", " ")
  html_content <- str_replace_all(html_content, "<td[^>]*>", " ")
  html_content <- str_replace_all(html_content, "<meta[^>]*>", " ")
  html_content <- str_replace_all(html_content, "</td>", " ")
  html_content <- str_replace_all(html_content, "</tr>", " ")
  html_content <- str_replace_all(html_content, "<tr[^>]*>", " ")
  html_content <- str_replace_all(html_content, "\\s+", " ")
  html_content <- str_replace_all(html_content, "<center[^>]*>", " ")
  html_content <- str_replace_all(html_content, "</center[^>]*>", " ")
  html_content <- str_replace_all(html_content, "<table[^>]*>", " ")
  html_content <- str_replace_all(html_content, "</table[^>]*>", " ")
  html_content <- str_replace_all(html_content, "</u> <u>", " ")
  html_content <- str_replace_all(html_content, "</u><u>", " ")
  html_content <- str_replace_all(html_content, ' </pre>', ' ')
  html_content <- str_replace_all(html_content, '<font[^>]*>', '')
  html_content <- str_replace_all(html_content, '</font>', '')
  html_content <- str_replace_all(html_content, '<!-- field: [A-Za-z]+ -->', '')
  html_content <- str_replace_all(html_content, '<!-- field: -->', '')
  html_content <- str_replace_all(html_content, '</body>', '')
  html_content <- str_replace_all(html_content, '<strong>', '')
  html_content <- str_replace_all(html_content, '</strong>', '')
  html_content <- str_replace_all(html_content, '<code>', '')
  html_content <- str_replace_all(html_content, '</code>', '')
  html_content <- str_replace_all(html_content, '<colgroup[^>]*>', '')
  html_content <- str_replace_all(html_content, '</colgroup>', '')
  html_content <- str_replace_all(html_content, '</u> [0-9]{1,2} <u class="amendmentInsertedText">', '')
  # Remove embedded CSS rules like `.highlight { ... }` or `.Page1::before { ... }`
  html_content <- str_remove_all(html_content, "\\.[^{]+\\{[^}]+\\}")
  
  # Remove remaining style tags (already in your function, kept for completeness)
  html_content <- str_replace_all(html_content, "<style>", "")
  html_content <- str_replace_all(html_content, "</style>", "")
  
  html_content <- str_trim(html_content)
  return(html_content)
}

scrape_text <- function(UUID, bill_id){
  message(UUID)
  TEXT_OUTPUT_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/delaware'
  url <- build_url(bill_id)
  page <- read_html(url)
  
  # Text links
  text_link <- page |> html_nodes(".file-link-html") |> html_attr("href")
  text_link <- glue("https://legis.delaware.gov{text_link}") |> str_subset("GetHtmlDocument\\?fileAttachmentId=")
  
  lapply(text_link, function(link){
    # Parse text
    text <- read_html(link) |> html_nodes("p") |> as.character() |> paste(collapse = "\n") |> clean_html() |> str_squish() |> str_trim()
    dir_create(glue("{TEXT_OUTPUT_PATH}/{UUID}"))
    # Create a filename based on the UUID and link
    filename <- basename(link) |> str_remove("^GetHtmlDocument\\?fileAttachmentId=")
    
    # Write the text to a file
    write_lines(text, path = glue("{TEXT_OUTPUT_PATH}/{UUID}/{UUID}_{filename}.txt"))
  })

}

# process bills
bill_xwalk <- readRDS("text/state-scrapers/de_legislation_data.rds")

vrleg_master_file <- readRDS("~/Desktop/GitHub/election-roll-call/bills/vrleg_master_file.rds")
master <- vrleg_master_file |> 
  filter(STATE == 'DE' & YEAR %in% c(1995:2014)) |>
  mutate(
    bill_id = str_remove_all(UUID, "DE"),
    year = str_extract(bill_id, "^[0-9]{4}"),
    bill_type = str_extract(bill_id, "[A-Z]+"),
    bill_type = case_match(
      bill_type,
      "H" ~ "HB",
      "S" ~ "SB",
      .default = bill_type
    ),
    bill_number = str_extract(bill_id, "[0-9]+$"),
    session = case_when(
      year %in% c('2001','2002') ~ "141st (2001 - 2002)",
      year %in% c('2003','2004') ~ "142nd (2003 - 2004)",
      year %in% c('2005','2006') ~ "143rd (2005 - 2006)",
      year %in% c('2007','2008') ~ "144th (2007 - 2008)",
      year %in% c('2009','2010') ~ "145th (2009 - 2010)",
      year %in% c('2011','2012') ~ "146th (2011 - 2012)",
      year %in% c('2013','2014') ~ "147th (2013 - 2014)"
    ),
    bill_number = glue("{bill_type} {bill_number}")
  ) |>
  select(UUID, session, bill_number)

master <- master |>
  left_join(
    bill_xwalk |> 
      group_by(LegislationNumber, AssemblyName) |> 
      slice_max(order_by = LegislationId, n = 1) |> 
      ungroup() |>
      select(LegislationId, LegislationNumber, AssemblyName), 
    by = c("bill_number" = "LegislationNumber", "session" = "AssemblyName"))

master |>
  select(UUID, bill_id = LegislationId) |>
  future_pmap(scrape_text, .progress = TRUE)