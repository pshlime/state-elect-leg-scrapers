##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Download OH Text
## Date: June 2025
## Author: Joe Loffredo
##################################################

rm(list = ls())
gc()

library(tidyverse)
library(rvest)
library(glue)
library(fs)
library(furrr)

plan(multisession, workers = 8)

build_url <- function(session, bill_number) {
  glue("https://www.legislature.ohio.gov/legislation/{session}/{bill_number}")
}

scrape_text <- function(UUID, session, bill_number){
  message(UUID)
  
  TEXT_OUTPUT_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/ohio'
  
  url <- build_url(session, bill_number)
  response <- httr::GET(url, config = httr::config(ssl_verifypeer = FALSE, followlocation = TRUE))
  
  if(response$status_code != 200){
    message(url)
    message(glue("Failed to fetch {UUID} - status code: {response$status_code}"))
    return(NULL)
  } else{
    page_text <- httr::content(response, "text")
    page <- read_html(page_text)
    
    text_links <- page |> 
      html_nodes("a") |> 
      html_attr("href") |> 
      str_subset("pdf") |>
      str_subset("legislation") |>
      unique()
    
    if(!is_empty(text_links)){
      dir_create(glue("{TEXT_OUTPUT_PATH}/{UUID}"))
      
      lapply(text_links, function(link) {
        file_name <- link |> 
          str_remove_all("https://search-prod.lis.state.oh.us/api/v2/general_assembly_[0-9]{1,3}/legislation/") |>
          str_replace_all("/", "_") |>
          str_replace("_pdf_",".pdf")
        
        file_path <- glue("{TEXT_OUTPUT_PATH}/{UUID}/{file_name}")
        
        download.file(link, file_path)
      })
    }
  }
  Sys.sleep(5)  # To avoid overwhelming the server
}

vrleg_master_file <- readRDS("~/Desktop/GitHub/election-roll-call/bills/vrleg_master_file.rds")
master <- vrleg_master_file |> 
  filter(STATE == 'OH'  & (YEAR %in% c(1995:2010) | YEAR %in% c(2011:2014) & is.na(ls_bill_id))) |>
  mutate(
    bill_id = str_remove_all(UUID, "OH"),
    year = str_extract(bill_id, "^[0-9]{4}"),
    session = case_when(
      year %in% c("2013", "2014") ~ '130',
      year %in% c("2011", "2012") ~ '129',
      year %in% c("2009", "2010") ~ '128',
      year %in% c("2007", "2008") ~ '127',
      year %in% c("2005", "2006") ~ '126',
      year %in% c("2003", "2004") ~ '125',
      year %in% c("2001", "2002") ~ '124',
      TRUE ~ NA_character_
    ),
    bill_type = str_extract(bill_id, "[A-Z]+"),
    bill_type = case_match(
      bill_type,
      "H" ~ "HB",
      "S" ~ "SB",
      .default = bill_type
    ),
    bill_number = str_extract(bill_id, "[0-9]+$"),
    bill_number = glue("{bill_type}{bill_number}") |> str_to_lower()
  ) |>
  select(UUID, session, bill_number) |>
  distinct()

master |>
  filter(!(UUID %in% list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/ohio"))) |>
  future_pmap(scrape_text, .progress = T)

bill_text_files <- data.frame(
  file_path = list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/ohio", pattern = "*.pdf", full.names = TRUE, recursive = TRUE)) |>
  mutate(
    file_name = basename(file_path),
    UUID = str_remove(file_path, file_name) |> basename()) |>
  group_by(UUID) |>
  slice_max(order_by = file_name, n = 1) |>
  ungroup() |>
  select(UUID, file_path) |>
  write_csv("text/state-scrapers/oh_bill_text_files.csv")
