##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Download NE Text
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

scrape_text <- function(UUID, session, bill_number){
  message(UUID)
  
  TEXT_OUTPUT_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/nebraska'
  document_types <- c('Intro','Final','Slip')
  
  for(d in document_types) {
    url <- glue("https://www.nebraskalegislature.gov/FloorDocs/{session}/PDF/{d}/{bill_number}.pdf")
    response <- httr::GET(url, config = httr::config(ssl_verifypeer = FALSE, followlocation = TRUE))
    
    if(response$status_code != 200){
      message(url)
      message(glue("Failed to fetch {UUID} - status code: {response$status_code}"))
      return(NULL)
    } else{
      dir_create(glue("{TEXT_OUTPUT_PATH}/{UUID}"))
      
      file_name <- glue("{UUID}_{d}.pdf")
      download.file(url, destfile = glue("{TEXT_OUTPUT_PATH}/{UUID}/{file_name}"), mode = "wb")
    }
  }
}

vrleg_master_file <- readRDS("~/Desktop/GitHub/election-roll-call/bills/vrleg_master_file.rds")
master <- vrleg_master_file |> 
  filter(STATE == 'NE' & (YEAR %in% c(1995:2010) | YEAR %in% c(2011:2014) & is.na(ls_bill_id))) |>
  mutate(
    bill_id = str_remove_all(UUID, "NE"),
    year = str_extract(bill_id, "^[0-9]{4}"),
    session = case_when(
      year %in% c("2013", "2014") ~ "103",
      year %in% c("2011", "2012") ~ "102",
      year %in% c("2009", "2010") ~ "101",
      year %in% c("2007", "2008") ~ "100",
      year %in% c("2005", "2006") ~ "99",
      year %in% c("2003", "2004") ~ "98",
      year %in% c("2001", "2002") ~ "97",
      TRUE ~ NA_character_
    ),
    bill_type = str_extract(bill_id, "[A-Z]+"),
    bill_type = case_match(
      bill_type,
      "L" ~ "LB",
      .default = bill_type
    ),
    bill_number = str_remove(bill_id, "[0-9]{4}[LR]{1,2}"),
    bill_number = glue("{bill_type}{bill_number}")
  ) |>
  select(UUID, session, bill_number)

master |>
  filter(!(UUID %in% list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/nebraska"))) |>
  future_pmap(scrape_text, .progress = T)

# precedence 
precedence <- c("_Intro.pdf" = 1, "_Final.pdf" = 2, "_Slip.pdf" = 3)

bill_text_files <- data.frame(
  file_path = list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/nebraska", pattern = "*.pdf", full.names = TRUE, recursive = TRUE)) |>
  mutate(
    file_name = basename(file_path),
    version = str_extract(file_name, "_(Intro|Final|Slip)\\.pdf$"),
    rank = precedence[version],
    UUID = str_remove(file_path, file_name) |> basename()) |>
  group_by(UUID) |>
  slice_max(order_by = rank, n = 1) |>
  ungroup() |>
  select(UUID, file_path) |>
  write_csv("text/state-scrapers/ne_bill_text_files.csv")
