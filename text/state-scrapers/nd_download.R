##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Download ND Text
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

plan(multisession, workers = 11)

build_url <- function(session, bill_number) {
  glue("https://ndlegis.gov/assembly/{session}/regular/bill-index/bi{bill_number}.html")
}

scrape_text <- function(UUID, session, bill_number){
  message(UUID)
  
  TEXT_OUTPUT_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/north_dakota'
  
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
      html_nodes(".legis-link") |> 
      html_attr("href") |> 
      str_subset("pdf$") |>
      unique() |>
      str_remove_all("^\\.\\./")
    
    
    text_links <- glue("https://ndlegis.gov/assembly/{session}/regular/{text_links}")
    
    if(!is_empty(text_links)){
      dir_create(glue("{TEXT_OUTPUT_PATH}/{UUID}"))
      
      lapply(text_links, function(link) {
        file_name <- basename(link)
        file_path <- glue("{TEXT_OUTPUT_PATH}/{UUID}/{file_name}")
        
        download.file(link, file_path, mode = "wb")
      })
    }
  }

}

vrleg_master_file <- readRDS("~/Desktop/GitHub/election-roll-call/bills/vrleg_master_file.rds")
master <- vrleg_master_file |> 
  filter(STATE == 'ND' & (YEAR %in% c(1995:2014))) |>
  mutate(
    bill_id = str_remove_all(UUID, "ND"),
    year = str_extract(bill_id, "^[0-9]{4}"),
    session = case_when(
      year %in% c("2013", "2014") ~ '63-2013',
      year %in% c("2011", "2012") ~ '62-2011',
      year %in% c("2009", "2010") ~ '61-2009',
      year %in% c("2007", "2008") ~ '60-2007',
      year %in% c("2005", "2006") ~ '59-2005',
      year %in% c("2003", "2004") ~ '58-2003',
      year %in% c("2001", "2002") ~ '57-2001',
      TRUE ~ NA_character_
    ),
    bill_number = str_extract(bill_id, "[0-9]+$"),
  ) |>
  select(UUID, session, bill_number) |>
  distinct()

master |>
  filter(!(UUID %in% list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/north_dakota"))) |>
  future_pmap(scrape_text, .progress = T)

bill_text_files <- data.frame(
  file_path = list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/north_dakota", pattern = "*.pdf", full.names = TRUE, recursive = TRUE)) |>
  mutate(
    file_name = basename(file_path),
    UUID = str_remove(file_path, file_name) |> basename()) |>
  group_by(UUID) |>
  slice_max(order_by = file_name, n = 1) |>
  ungroup() |>
  select(UUID, file_path) |>
  write_csv("text/state-scrapers/nd_bill_text_files.csv")
