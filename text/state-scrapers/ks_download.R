##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Download KS Text
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

build_url <- function(session, year, bill_number){
  if(session %in% c('2011_12', '2013_14')){
    glue("https://www.kslegislature.gov/li_{year}/b{session}/measures/{bill_number}/")
  } else{
    session_end <- case_match(
      session,
      "2001_02" ~ "2002",
      "2003_04" ~ "2004",
      "2005_06" ~ "2006",
      "2007_08" ~ "2008",
      "2009_10" ~ "2010"
    )
    
    bill_number <- str_replace_all(
      bill_number,
      c("hb" = "H_Bill_",
        "sb" = "S_Bill_",
        "hcr" = "H_Con_Res_",
        "scr" = "S_Con_Res_",
        "hr" = "H_Res_",
        "sr" = "S_Res_")
    )
    
    glue("https://www.kslegislature.gov/historical_data/bills/{session_end}/{year}_{bill_number}.pdf")
  }
}

scrape_text <- function(UUID, session, year, bill_number){
  message(UUID)
  TEXT_OUTPUT_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/kansas'
  
  url <- build_url(session, year, bill_number)
  response <- httr::GET(url, config = httr::config(ssl_verifypeer = FALSE))
  
  if(response$status_code != 200){
    message(url)
    message(glue("Failed to fetch {UUID} - status code: {response$status_code}"))
    return(NULL)
  } else{
    dir_create(glue("{TEXT_OUTPUT_PATH}/{UUID}"))
    
    if(session %in% c('2011_12', '2013_14')){
      page_text <- httr::content(response, "text")
      page <- read_html(page_text)
      
      links <- page |>
        html_nodes("a") |>
        html_attr("href") |>
        str_subset("\\.pdf$") |>
        str_subset(glue("documents/{bill_number}"))
      
      links <- glue("https://www.kslegislature.gov{links}")
      
      sapply(links, function(url){
        file_name <- basename(url)
        dest_file <- glue("{TEXT_OUTPUT_PATH}/{UUID}/{file_name}")
        download.file(url, destfile = dest_file, mode = "wb")
      })
    } else{
      file_name <- basename(url)
      dest_file <- glue("{TEXT_OUTPUT_PATH}/{UUID}/{file_name}")
      download.file(url, destfile = dest_file, mode = "wb")
    }
  }
}

vrleg_master_file <- readRDS("~/Desktop/GitHub/election-roll-call/bills/vrleg_master_file.rds")
master <- vrleg_master_file |> 
  filter(STATE == 'KS' & YEAR %in% c(1995:2014)) |>
  mutate(
    bill_id = str_remove_all(UUID, "KS"),
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
      year %in% c('2001', '2002') ~ '2001_02',
      year %in% c('2003', '2004') ~ '2003_04',
      year %in% c('2005', '2006') ~ '2005_06',
      year %in% c('2007', '2008') ~ '2007_08',
      year %in% c('2009', '2010') ~ '2009_10',
      year %in% c('2011', '2012') ~ '2011_12',
      year %in% c('2013', '2014') ~ '2013_14'
    ),
    bill_number = glue("{bill_type}{bill_number}") |> str_to_lower()
  ) |>
  select(UUID, session, year, bill_number)

master |>
  filter(!(UUID %in% list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/kansas"))) |>
  future_pmap(scrape_text)

bill_text_files <- data.frame(
  file_path = list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/kansas", pattern = "*.pdf", full.names = TRUE, recursive = TRUE)) |>
  mutate(
    file_name = basename(file_path),
    UUID = str_remove(file_path, file_name) |> basename()) |>
  select(UUID, file_path) |>
  write_csv("text/state-scrapers/ks_bill_text_files.csv")
