##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Scrape AK Bill Text
## Date: May 2025
## Author: Joe Loffredo
##################################################

rm(list = ls())
gc()

library(tidyverse)
library(rvest)
library(glue)
library(furrr)
library(fs)

plan(multisession, workers = 11)

clean_html <- function(html_content) {
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

build_url <- function(session, bill_number){
  glue("https://www.akleg.gov/basis/Bill/Detail/{session}?Root={bill_number}#tab1_4")
}

scrape_text <- function(UUID, session, bill_number){
  message(UUID)
  TEXT_OUTPUT_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/alaska'
  
  url <- build_url(session, bill_number)
  
  text_links <- read_html(url) |>
    html_nodes("#tab1_4 a") |>
    html_attr("href") |>
    str_subset("Bill/Text/")
  
  text_links <- glue("https://www.akleg.gov{text_links}")
  
  lapply(text_links, function(link) {
    tryCatch({
      text <- read_html(link) |>
        html_nodes(".heading-container") |>
        as.character() |>
        clean_html() |>
        str_trim() |>
        str_squish()
      
      dir_create(glue("{TEXT_OUTPUT_PATH}/{UUID}"))
      # Create a filename based on the UUID and link
      filename <- basename(link) |> str_remove("^[0-9]{2}\\?Hsid=")
      # Write the text to a file
      write_lines(text, path = glue("{TEXT_OUTPUT_PATH}/{UUID}/{filename}.txt"))
      
    }, error = function(e) {
      message(glue("Error scraping {link}: {e$message}"))
    })
  })
}

vrleg_master_file <- readRDS("~/Desktop/GitHub/election-roll-call/bills/vrleg_master_file.rds")
master <- vrleg_master_file |> 
  filter(STATE == 'AK' & YEAR %in% c(1995:2014)) |>
  mutate(
    bill_id = str_remove_all(UUID, "AK"),
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
      year %in% c('1999','2000') ~ '21',
      year %in% c('2001','2002') ~ '22',
      year %in% c('2003','2004') ~ '23',
      year %in% c('2005','2006') ~ '24',
      year %in% c('2007','2008') ~ '25',
      year %in% c('2009','2010') ~ '26',
      year %in% c('2011','2012') ~ '27',
      year %in% c('2013','2014') ~ '28'
    ),
    bill_number = glue("{bill_type}{bill_number}")
  ) |>
  select(UUID, session, bill_number)

master |>
  future_pmap(scrape_text)

