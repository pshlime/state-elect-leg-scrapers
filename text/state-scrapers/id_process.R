##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Download ID Text
## Date: May 2025
## Author: Joe Loffredo
##################################################

rm(list = ls())
gc()

library(tidyverse)
library(rvest)
library(glue)
library(fs)
library(reticulate)

source_python("text/state-scrapers/id_parse_pdf.py")

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
  html_content <- str_replace_all(html_content, "<strike class=\"amendmentDeletedText\"> </strike>", "")
  html_content <- str_replace_all(html_content, "</strike> [0-9]{1,2} <strike class=\"amendmentDeletedText\">", "")
  
  html_content <- str_trim(html_content)
  return(html_content)
}

build_url <- function(session, bill_number){
  glue("https://legislature.idaho.gov/sessioninfo/{session}/legislation/{bill_number}")
}

scrape_text <- function(UUID, session, bill_number){
  message(UUID)
  TEXT_OUTPUT_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/idaho'
  
  url <- build_url(session, bill_number)
  page <- read_html(url)
  
  if(session %in% c('2001','2002','2003','2004','2005','2006','2007','2008')){
    dir_create(glue("{TEXT_OUTPUT_PATH}/{UUID}"))
    text <- page |> 
      html_nodes("pre") |> 
      as.character() |> 
      clean_html() |> 
      str_trim() |> 
      str_squish() |> 
      str_subset("LEGISLATURE OF THE STATE OF IDAHO") |>
      str_remove_all("]]]] LEGISLATURE OF THE STATE OF IDAHO ]]]] ")
    
    for(t in 1:length(text)){
      # Write the text to a file
      write_lines(text[t], path = glue("{TEXT_OUTPUT_PATH}/{UUID}/{UUID}_{t}.txt"))
    }
  } else{
    dir_create(glue("{TEXT_OUTPUT_PATH}/{UUID}"))
    
    text_link <- page |> html_nodes(".plain") |> html_attr("href") |> str_subset("SOP", negate = T)
    text_link <- glue("https://legislature.idaho.gov{text_link}") |> tail(1)
    
    dest_file_path <- glue("{TEXT_OUTPUT_PATH}/{UUID}/{UUID}_{basename(text_link)}")
    download.file(text_link, destfile = dest_file_path)
    
    sync_scrape_text(dest_file_path)
  }
}

vrleg_master_file <- readRDS("~/Desktop/GitHub/election-roll-call/bills/vrleg_master_file.rds")
master <- vrleg_master_file |> 
  filter(STATE == 'ID' & YEAR %in% 1995:2014) |>
  mutate(
    bill_id = str_remove_all(UUID, "ID"),
    session = str_extract(bill_id, "^[0-9]{4}"),
    bill_type = str_extract(bill_id, "[A-Z]+"),
    bill_number = str_extract(bill_id, "[0-9]+$"),
    bill_number = case_when(
      bill_type %in% c("H", "S") ~ str_pad(bill_number, 4, pad = "0"),
      TRUE ~ str_pad(bill_number, 3, pad = "0")
    ),
    bill_number = glue("{bill_type}{bill_number}")
  ) |>
  select(UUID, session, bill_number)

master |>
  filter(!(UUID %in% list.files("/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/idaho"))) |>
  pmap(scrape_text, .progress = T)

