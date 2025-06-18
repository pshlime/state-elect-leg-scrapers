##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Download OR Text
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

# Create link look up table 
archived_links <- read_csv("text/state-scrapers/or_archived_bill_links.csv") |>
  mutate(
    title = str_replace(title, "—","-") |> str_trim(),
    bill_id = str_extract(title, "^[^-]+") |> str_trim(),
    version = str_extract(title, "(?<=- ).*") |> str_trim()
  ) |>
  group_by(session_name, bill_id) |>
  slice(1) |>
  ungroup() |>
  select(session_name, bill_id, version, full_url)

api_links <- read_csv("text/state-scrapers/or_api_bill_links.csv") |>
  mutate(
    title = str_replace(title, "[\u2013\u2014\u2012]","-") |> str_trim(),
    bill_id = str_extract(title, "^[^-]+") |> str_trim(),
    version = basename(full_url) |> str_trim()
  ) |>
  group_by(session_name, bill_id) |>
  slice(1) |>
  ungroup() |>
  select(session_name, bill_id, version, full_url)

text_links <- bind_rows(archived_links, api_links)

build_url <- function(session, bill_number) {
  text_links |> filter(session_name == session & bill_id == bill_number) |> pull(full_url)
}

scrape_text <- function(UUID, session, bill_number){
  message(UUID)
  
  TEXT_OUTPUT_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/oregon'
  
  url <- build_url(session, bill_number)
  if(!is_empty(url)){
    response <- httr::GET(url, config = httr::config(ssl_verifypeer = FALSE, followlocation = TRUE))
  } else{
    message(glue("No URL found for {UUID}"))
    return(NULL)
  }
  
  if(response$status_code != 200){
    message(url)
    message(glue("Failed to fetch {UUID} - status code: {response$status_code}"))
    return(NULL)
  } else{
    dir_create(glue("{TEXT_OUTPUT_PATH}/{UUID}"))
    
    file_name <- glue("{TEXT_OUTPUT_PATH}/{UUID}/{UUID}.pdf")
    
    download.file(url, file_name)
  }
}

vrleg_master_file <- readRDS("~/Desktop/GitHub/election-roll-call/bills/vrleg_master_file.rds")
master <- vrleg_master_file |> 
  filter(STATE == 'OR'  & (YEAR %in% c(1995:2010) | YEAR %in% c(2011:2014) & is.na(ls_bill_id))) |>
  mutate(
    bill_id = str_remove_all(UUID, "OR"),
    year = str_extract(bill_id, "^[0-9]{4}"),
    session = case_when(
      year == '2014' ~ '2014 Regular Session',
      year == '2013' ~ '2013 Regular Session',
      year == '2012' ~ '2012 Regular Session',
      year == '2011' ~ '2011 Regular Session',
      year == '2010' ~ '2010 Regular Session',
      year == '2009' ~ '2009 Regular Session',
      year == '2008' ~ '2008 Regular Session',
      year == '2007' ~ '2007 Regular Session',
      year %in% c('2005', '2006') ~ '2005 Regular Session',
      year %in% c('2003', '2004') ~ '2003 Regular Session',
      year %in% c('2001', '2002') ~ '2001 Regular Session',
      TRUE ~ NA_character_
    ),
    bill_type = str_extract(bill_id, "[A-Z]+"),
    bill_type = case_when(
      session %in% c('2001 Regular Session', '2003 Regular Session', '2005 Regular Session') & bill_type == 'H' ~ "House Bill",
      session %in% c('2001 Regular Session', '2003 Regular Session', '2005 Regular Session') & bill_type == 'HCR' ~ "House Concurrent Resolution",
      session %in% c('2001 Regular Session', '2003 Regular Session', '2005 Regular Session') & bill_type == 'HJR' ~ "House Joint Resolution",
      session %in% c('2001 Regular Session', '2003 Regular Session', '2005 Regular Session') & bill_type == 'HJRR' ~ "House Joint Resolution",
      session %in% c('2001 Regular Session', '2003 Regular Session', '2005 Regular Session') & bill_type == 'HJM' ~ "House Joint Memorial",
      session %in% c('2001 Regular Session', '2003 Regular Session', '2005 Regular Session') & bill_type == 'HM' ~ "House Memorial",
      session %in% c('2001 Regular Session', '2003 Regular Session', '2005 Regular Session') & bill_type == 'S' ~ "Senate Bill",
      session %in% c('2001 Regular Session', '2003 Regular Session', '2005 Regular Session') & bill_type == 'SCR' ~ "Senate Concurrent Resolution",
      session %in% c('2001 Regular Session', '2003 Regular Session', '2005 Regular Session') & bill_type == 'SJR' ~ "Senate Joint Resolution",
      session %in% c('2001 Regular Session', '2003 Regular Session', '2005 Regular Session') & bill_type == 'SJRR' ~ "Senate Joint Resolution",
      session %in% c('2001 Regular Session', '2003 Regular Session', '2005 Regular Session') & bill_type == 'SJM' ~ "Senate Joint Memorial",
      session %in% c('2001 Regular Session', '2003 Regular Session', '2005 Regular Session') & bill_type == 'SM' ~ "Senate Memorial",
      !(session %in% c('2001 Regular Session', '2003 Regular Session', '2005 Regular Session')) & bill_type == 'H' ~ "HB",
      !(session %in% c('2001 Regular Session', '2003 Regular Session', '2005 Regular Session')) & bill_type == 'S' ~ "SB",
      !(session %in% c('2001 Regular Session', '2003 Regular Session', '2005 Regular Session')) & bill_type == 'SJRR' ~ "SJR",
      !(session %in% c('2001 Regular Session', '2003 Regular Session', '2005 Regular Session')) & bill_type == 'HJRR' ~ "HJR",
      TRUE ~ bill_type
    ), 
    bill_number = str_extract(bill_id, "[0-9]+$"),
    bill_number = glue("{bill_type} {bill_number}")
  ) |>
  select(UUID, session, bill_number)

master |>
  filter(!(UUID %in% list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/oregon"))) |>
  future_pmap(scrape_text, .progress = T)

bill_text_files <- data.frame(
  file_path = list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/oregon", pattern = "*.pdf", full.names = TRUE, recursive = TRUE)) |>
  mutate(
    file_name = basename(file_path),
    UUID = str_remove(file_path, file_name) |> basename()) |>
  select(UUID, file_path) |>
  write_csv("text/state-scrapers/or_bill_text_files.csv")

