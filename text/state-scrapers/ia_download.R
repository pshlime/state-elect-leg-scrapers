##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Parse IA Text
## Date: May 2025
## Author: Joe Loffredo
##################################################

rm(list = ls())
gc()

library(tidyverse)
library(rvest)
library(glue)
library(fs)
library(furrr)

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
  html_content <- str_replace_all(html_content, '<u class=\"amendmentInsertedText\"> </u>', '')
  html_content <- str_replace_all(html_content, ' [0-9]{1,2} [0-9]{1,2} ', ' ')
  # Remove embedded CSS rules like `.highlight { ... }` or `.Page1::before { ... }`
  html_content <- str_remove_all(html_content, "\\.[^{]+\\{[^}]+\\}")
  
  # Remove remaining style tags (already in your function, kept for completeness)
  html_content <- str_replace_all(html_content, "<style>", "")
  html_content <- str_replace_all(html_content, "</style>", "")
  
  html_content <- str_trim(html_content)
  return(html_content)
}

build_url <- function(session, bill_number){
  if(session %in% c('80', '81', '82', '83', '84', '85')){
    glue("https://www.legis.iowa.gov/docs/publications/LGI/{session}/Attachments/{bill_number}.html")
  } else{
    glue("https://www.legis.iowa.gov/docs/publications/LGI/{session}/{bill_number}.pdf")
  }
}

scrape_text <- function(UUID, session, bill_number){
  message(UUID)
  TEXT_OUTPUT_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/iowa'
  
  url <- build_url(session, bill_number)
  
  if(session %in% c('80', '81', '82', '83', '84', '85')){
    response <- httr::GET(url, config = httr::config(ssl_verifypeer = FALSE))
    if(response$status_code != 200){
      message(glue("Failed to fetch {UUID} - status code: {response$status_code}"))
      return(NULL)
    } else{
      page_text <- httr::content(response, "text")
      page <- read_html(page_text)
      text <- page |>
        html_nodes("pre") |> 
        as.character() |>
        clean_html() |> 
        str_trim() |>
        str_squish()
      
      dir_create(glue("{TEXT_OUTPUT_PATH}/{UUID}"))
      # Write the text to a file
      write_lines(text, path = glue("{TEXT_OUTPUT_PATH}/{UUID}/{UUID}.txt"))
    }
  } else{
    dir_create(glue("{TEXT_OUTPUT_PATH}/{UUID}"))
    
    dest_file <- glue("{TEXT_OUTPUT_PATH}/{UUID}/{UUID}.pdf")
    
    download.file(url, destfile = dest_file, mode = "wb")
  }
}

vrleg_master_file <- readRDS("~/Desktop/GitHub/election-roll-call/bills/vrleg_master_file.rds")
master <- vrleg_master_file |> 
  filter(STATE == 'IA' & YEAR %in% c(1995:2014)) |>
  mutate(
    bill_id = str_remove_all(UUID, "IA"),
    year = str_extract(bill_id, "^[0-9]{4}"),
    bill_type = str_extract(bill_id, "[A-Z]+"),
    bill_type = case_match(
      bill_type,
      "H" ~ "HF",
      "S" ~ "SF",
      .default = bill_type
    ),
    bill_number = str_extract(bill_id, "[0-9]+$"),
    session = case_when(
      year %in% c('2001', '2002') ~ '79',
      year %in% c('2003', '2004') ~ '80',
      year %in% c('2005', '2006') ~ '81',
      year %in% c('2007', '2008') ~ '82',
      year %in% c('2009', '2010') ~ '83',
      year %in% c('2011', '2012') ~ '84',
      year %in% c('2013', '2014') ~ '85'
    ),
    bill_number = glue("{bill_type}{bill_number}")
  ) |>
  select(UUID, session, bill_number)

master |>
  filter(!(UUID %in% list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/iowa"))) |>
  future_pmap(scrape_text)

bill_text_files <- data.frame(
  file_path = list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/iowa", pattern = "*.pdf", full.names = TRUE, recursive = TRUE)) |>
  mutate(
    file_name = basename(file_path),
    UUID = str_extract(file_name, "^[^_]+") |> str_remove(".pdf$")) |>
  select(UUID, file_path) |>
  write_csv("text/state-scrapers/ia_bill_text_files.csv")
