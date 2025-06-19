##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Downlaod AR Text
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

build_url <- function(session, bill_number){
  if(session %in% c('2001', '2003', '2005', '2007', '2009')){
    glue("https://arkleg.state.ar.us/Bills/Detail?id={bill_number}&ddBienniumSession={session}%2FR")
  } else{
    glue("https://arkleg.state.ar.us/Bills/Detail?id={bill_number}&ddBienniumSession={session}%2F{session}R")
  }
  
  
}

scrape_text <- function(UUID, session, bill_number){
  message(UUID)
  TEXT_OUTPUT_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/arkansas'
  
  url <- build_url(session, bill_number)
  
  check_page <- httr::GET(url, httr::config(followlocation = FALSE))  # don't follow redirect
  if(check_page$status_code != 302){
    page <- read_html(url)
    
    text_links <- read_html(url) |>
      html_elements("a[href$='.pdf']") |> 
      html_attr("href") |>
      str_subset("Bills")
    
    text_links <- glue("https://arkleg.state.ar.us{text_links}")
    
    lapply(text_links, function(link) {
      tryCatch({
        
        dir_create(glue("{TEXT_OUTPUT_PATH}/{UUID}"))
        # Create a filename based on the UUID and link
        filename <- glue("{TEXT_OUTPUT_PATH}/{UUID}/{UUID}_{basename(link)}")
        download.file(link, filename, mode = "wb")
        
      }, error = function(e) {
        message(glue("Error scraping {link}: {e$message}"))
      })
    })
  }
}

vrleg_master_file <- readRDS("~/Desktop/GitHub/election-roll-call/bills/vrleg_master_file.rds")
master <- vrleg_master_file |> 
  filter(STATE == 'AR' & YEAR %in% c(1995:2014)) |>
  mutate(
    bill_id = str_remove_all(UUID, "AR"),
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
      year %in% c('1999','2000') ~ '1999',
      year %in% c('2001','2002') ~ '2001',
      year %in% c('2003','2004') ~ '2003',
      year %in% c('2005','2006') ~ '2005',
      year %in% c('2007','2008') ~ '2007',
      year %in% c('2009','2010') ~ '2009',
      year %in% c('2011','2012') ~ '2011',
      year %in% c('2013','2014') ~ '2013'
    ),
    bill_number = glue("{bill_type}{bill_number}")
  ) |>
  select(UUID, session, bill_number)

master |>
  future_pmap(scrape_text)

bill_text_files <- data.frame(
  file_path = list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/arkansas", pattern = "*.pdf", full.names = TRUE, recursive = TRUE)) |>
  mutate(
    file_name = basename(file_path),
    UUID = str_extract(file_name, "^[^_]+")) |>
  select(UUID, file_path) |>
  write_csv("text/state-scrapers/ar_bill_text_files.csv")

