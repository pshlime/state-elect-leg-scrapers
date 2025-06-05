##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Download ME Text
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

source_python("text/state-scrapers/me_retrieve_link.py")

clean_html <- function(html_content) {
  html_content <- str_replace_all(
    html_content,
    '<span style="text-decoration:underline;\\s*">',
    '<<INSERT_OPEN>>'
  )
  html_content <- str_replace_all(
    html_content,
    '<span style="text-decoration:line-through;\\s*">',
    '<<DELETE_OPEN>>'
  )
  
  html_content <- str_replace_all(html_content, '</span>', '<<CLOSE_SPAN>>')
  
  html_content <- str_replace_all(html_content, '<<INSERT_OPEN>>', '<u class="amendmentInsertedText">')
  html_content <- str_replace_all(html_content, '<<DELETE_OPEN>>', '<strike class="amendmentDeletedText">')
  
  while (str_detect(html_content, '<u class="amendmentInsertedText">.*?<<CLOSE_SPAN>>')) {
    html_content <- str_replace(
      html_content,
      '(<u class="amendmentInsertedText">.*?)<<CLOSE_SPAN>>',
      '\\1</u>'
    )
  }
  while (str_detect(html_content, '<strike class="amendmentDeletedText">.*?<<CLOSE_SPAN>>')) {
    html_content <- str_replace(
      html_content,
      '(<strike class="amendmentDeletedText">.*?)<<CLOSE_SPAN>>',
      '\\1</strike>'
    )
  }
  
  html_content <- str_replace_all(html_content, '<<CLOSE_SPAN>>', '')
  
  html_content <- str_replace_all(html_content, '<u>', '<u class="amendmentInsertedText">')
  html_content <- str_replace_all(html_content, '<s>', '<strike class="amendmentDeletedText">')
  html_content <- str_replace_all(html_content, '</s>', '</strike>')
  
  html_content <- str_replace_all(html_content, "<p[^>]*>", " ")
  html_content <- str_replace_all(html_content, "</p>", " ")
  html_content <- str_replace_all(html_content, "<div[^>]*>", " ")
  html_content <- str_replace_all(html_content, "</div>", " ")
  html_content <- str_replace_all(html_content, "<a[^>]*>", " ")
  html_content <- str_replace_all(html_content, "</a>", " ")
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
  html_content <- str_remove_all(html_content, "\\.[^{]+\\{[^}]+\\}")
  html_content <- str_replace_all(html_content, "<style>", "")
  html_content <- str_replace_all(html_content, "</style>", "")
  html_content <- str_replace_all(html_content, "<strike class=\"amendmentDeletedText\"> </strike>", "")
  html_content <- str_replace_all(html_content, "</strike> [0-9]{1,2} <strike class=\"amendmentDeletedText\">", "")
  html_content <- str_replace_all(html_content, "</u></u>", "</u>")
  html_content <- str_replace_all(html_content, "<!-- START OF BILL TEXT --->", "")
  html_content <- str_replace_all(html_content, "<!-- END OF BILL TEXT --->", "")
  
  html_content <- str_trim(html_content)
  return(html_content)
}


scrape_text <- function(UUID, session, bill_number){
  message(UUID)
  TEXT_OUTPUT_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/maine'
  
  text_links <- retrieve_bill_text(session, bill_number)
  
  if(is_empty(text_links)){
    message(glue("Failed to links for {UUID}"))
    return(NULL)
  } else{
    dir_create(glue("{TEXT_OUTPUT_PATH}/{UUID}"))
    
    lapply(text_links, function(link) {
      tryCatch({
        page <- read_html(link)
        
        selector <- ifelse(session %in% c('120', '121', '122'), 'div center td', '.text')
        text <- page |> html_element(selector) |> as.character() |> clean_html() |> str_trim() |> str_squish()
        
        file_name <- basename(link) |> str_remove_all(".asp$")
        file_path <- glue("{TEXT_OUTPUT_PATH}/{UUID}/{file_name}.txt")
        writeLines(text, file_path)
        
      }, error = function(e) {
        message(glue("Error downloading {link} for {UUID}: {e$message}"))
      })
    })
    
  }
}

vrleg_master_file <- readRDS("~/Desktop/GitHub/election-roll-call/bills/vrleg_master_file.rds")
master <- vrleg_master_file |> 
  filter(STATE == 'ME' & YEAR %in% c(1995:2014)) |>
  mutate(
    bill_id = str_remove_all(UUID, "ME"),
    year = str_extract(bill_id, "^[0-9]{4}"),
    bill_type = str_extract(bill_id, "[A-Z]+"),
    bill_number = str_extract(bill_id, "[0-9]+$"),
    session = case_when(
      year %in% c('2001','2002') ~ '120',
      year %in% c('2003','2004') ~ '121',
      year %in% c('2005','2006') ~ '122',
      year %in% c('2007','2008') ~ '123',
      year %in% c('2009','2010') ~ '124',
      year %in% c('2011','2012') ~ '125',
      year %in% c('2013','2014') ~ '126'
    ),
    bill_type = case_when(
      bill_type == "H" & session %in% c('120', '121', '122', '123', '124') ~ "LD",
      bill_type == "S" & session %in% c('120', '121', '122', '123', '124') ~ "LD",
      bill_type == "H" & session %in% c('125', '126') ~ "HP",
      bill_type == "S" & session %in% c('125', '126') ~ "SP",
      TRUE ~ bill_type
    ),
    bill_number = glue("{bill_type}{bill_number}") |> str_remove_all("^LD")
  ) |>
  select(UUID, session, bill_number)

master |>
  filter(!str_detect(bill_number, "^LR")) |>
  filter(!(UUID %in% list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/maine"))) |>
  pmap(scrape_text)
