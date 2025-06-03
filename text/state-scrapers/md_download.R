##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Download MD Text
## Date: June 2025
## Author: Joe Loffredo
##################################################

rm(list = ls())
gc()

library(tidyverse)
library(rvest)
library(glue)
library(fs)
library(polite)
library(httr)
library(furrr)

#plan(multisession, workers = 11)

build_url <- function(session, bill_number) {
  if(session %in% c('2013rs', '2014rs')) {
    return(glue("https://mgaleg.maryland.gov/mgawebsite/Legislation/Details/{bill_number}/?ys={session}"))
  } else{
    glue("https://mgaleg.maryland.gov/mgawebsite/Search/Legislation?target=/{session}/billfile/{bill_number}.htm")
  }
  
}

scrape_text <- function(UUID, session, bill_number) {
  message(UUID)
  TEXT_OUTPUT_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/maryland'
  
  url <- build_url(session, bill_number)
  response <- httr::GET(url, config = httr::config(ssl_verifypeer = FALSE))
  
  if(response$status_code != 200){
    message(url)
    message(glue("Failed to fetch {UUID} - status code: {response$status_code}"))
    return(NULL)
  } else{
    dir_create(glue("{TEXT_OUTPUT_PATH}/{UUID}"))
    
    page_text <- httr::content(response, "text")
    page <- read_html(page_text)
    
    if(session %in% c('2013rs','2014rs')){
      text_links <- page |> html_nodes('#detailsDocuments a') |> html_attr('href') |> str_subset("bills|chapters")
      text_links <- glue("https://mgaleg.maryland.gov{text_links}")
    } else{
      text_links <- page |> html_nodes('a[href$=".pdf"]') |> html_attr('href') |> str_subset("bills|chapters") 
    }
    
    lapply(text_links, function(link) {
      file_name <- basename(link)
      file_path <- glue("{TEXT_OUTPUT_PATH}/{UUID}/{file_name}")
      download.file(link, file_path, mode = "wb")
    })
  }
}


vrleg_master_file <- readRDS("~/Desktop/GitHub/election-roll-call/bills/vrleg_master_file.rds")
master <- vrleg_master_file |> 
  filter(STATE == 'MD' & YEAR %in% c(1995:2014)) |>
  mutate(
    bill_id = str_remove_all(UUID, "MD"),
    year = str_extract(bill_id, "^[0-9]{4}"),
    session = case_match(
      year,
      "2001" ~ "2001rs",
      "2002" ~ "2002rs",
      "2003" ~ "2003rs",
      "2004" ~ "2004rs",
      "2005" ~ "2005rs",
      "2006" ~ "2006rs",
      "2007" ~ "2007rs",
      "2008" ~ "2008rs",
      "2009" ~ "2009rs",
      "2010" ~ "2010rs",
      "2011" ~ "2011rs",
      "2012" ~ "2012rs",
      "2013" ~ "2013rs",
      "2014" ~ "2014rs",
    ), 
    bill_type = str_extract(bill_id, "[A-Z]+"),
    bill_type = case_match(
      bill_type,
      "H" ~ "HB",
      "S" ~ "SB",
      "SJR" ~ "SJ",
      "HJR" ~ "HJ",
      .default = bill_type
    ),
    bill_number = str_extract(bill_id, "[0-9]+$"),
    bill_number = str_pad(bill_number, width = 4, side = "left", pad = "0"),
    bill_number = glue("{bill_type}{bill_number}")
  ) |>
  select(UUID, session, bill_number)

master |>
  filter(!(UUID %in% list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/maryland"))) |>
  future_pmap(scrape_text)

bill_text_files <- data.frame(
  file_path = list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/maryland", pattern = "*.pdf", full.names = TRUE, recursive = TRUE)) |>
  mutate(
    file_name = basename(file_path),
    UUID = str_remove(file_path, file_name) |> basename()) |>
  select(UUID, file_path) |>
  write_csv("text/state-scrapers/md_bill_text_files.csv")
