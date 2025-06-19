##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Download NV Text
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

nv_bill_links <- read_csv('text/state-scrapers/nv_bill_ids.csv')

scrape_text <- function(UUID, session, bill_number){
  message(UUID)
  
  TEXT_OUTPUT_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/nevada'
  
  url <- nv_bill_links |> filter(session_id == session & bill_id == bill_number) |> pull(link)
  if(!is_empty(url)){
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
        str_subset("Bills|bills") |> 
        str_subset("pdf$") |>
        str_subset("Amendments|amendments", negate = TRUE) |>
        unique()
      
      text_links <- glue("https://www.leg.state.nv.us{text_links}")
      
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
}

vrleg_master_file <- readRDS("~/Desktop/GitHub/election-roll-call/bills/vrleg_master_file.rds")
master <- vrleg_master_file |> 
  filter(STATE == 'NV' & (YEAR %in% c(1995:2014))) |>
  mutate(
    bill_id = str_remove_all(UUID, "NV"),
    year = str_extract(bill_id, "^[0-9]{4}"),
    session = case_when(
      year %in% c("2013", "2014") ~ '77th2013',
      year %in% c("2011", "2012") ~ '76th2011',
      year %in% c("2009", "2010") ~ "75th2009",
      year %in% c("2007", "2008") ~ "74th2007",
      year %in% c("2005", "2006") ~ "73rd2005",
      year %in% c("2003", "2004") ~ "72nd2003",
      year %in% c("2001", "2002") ~ "71st2001",
      TRUE ~ NA_character_
    ),
    bill_type = str_extract(bill_id, "[A-Z]+"),
    bill_type = case_match(
      bill_type,
      "S" ~ "SB",
      "A" ~ "AB",
      "SJRR" ~ "SJR",
      "AJRR" ~ "AJR",
      .default = bill_type
    ),
    bill_number = str_extract(bill_id, "[0-9]+$"),
    bill_number = glue("{bill_type}{bill_number}")
  ) |>
  select(UUID, session, bill_number) |>
  distinct()

master |>
  filter(!(UUID %in% list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/nevada"))) |>
  future_pmap(scrape_text, .progress = T)

# precedence 
get_rank <- function(path) {
  case_when(
    str_detect(path, "EN\\.pdf$") ~ 4,
    str_detect(path, "_R2\\.pdf$") ~ 3,
    str_detect(path, "R1\\.pdf$") ~ 2,
    TRUE ~ 1
  )
}

bill_text_files <- data.frame(
  file_path = list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/nevada", pattern = "*.pdf", full.names = TRUE, recursive = TRUE)) |>
  mutate(
    file_name = basename(file_path),
    version = str_extract(file_name, "_(Intro|Final|Slip)\\.pdf$"),
    rank = get_rank(file_name),
    UUID = str_remove(file_path, file_name) |> basename()) |>
  group_by(UUID) |>
  slice_max(order_by = rank, n = 1) |>
  ungroup() |>
  select(UUID, file_path) |>
  write_csv("text/state-scrapers/nv_bill_text_files.csv")
