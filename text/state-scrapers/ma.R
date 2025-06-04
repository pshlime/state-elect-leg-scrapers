##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Download MA Text
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

plan(multisession, workers = 11)

build_url <- function(session, bill_number) {
  glue("https://malegislature.gov/Bills/{session}/{bill_number}")
}

scrape_text <- function(UUID, session, bill_number) {
  message(UUID)
  TEXT_OUTPUT_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/massachusetts'
  
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
    
    text_link <- page |> html_nodes("a") |> html_attr("href") |> str_subset("/Text")
    text_link <- glue("https://malegislature.gov{text_link}")
    
    text <- read_html(text_link) |> 
      html_nodes("body") |> 
      html_text() |> 
      paste(collapse = "\n") |>
      str_trim() |>
      str_squish()
    
    write_lines(text, glue("{TEXT_OUTPUT_PATH}/{UUID}/{UUID}_html.txt"))
    
  }
}

vrleg_master_file <- readRDS("~/Desktop/GitHub/election-roll-call/bills/vrleg_master_file.rds")
master <- vrleg_master_file |> 
  filter(STATE == 'MA' & YEAR %in% c(2009:2014)) |>
  mutate(
    bill_id = str_remove_all(UUID, "MA"),
    year = str_extract(bill_id, "^[0-9]{4}"),
    session = case_match(
      year,
      "2009" ~ "186",
      "2010" ~ "186",
      "2011" ~ "187",
      "2012" ~ "187",
      "2013" ~ "188",
      "2014" ~ "188",
    ), 
    bill_type = str_extract(bill_id, "[A-Z]+"),
    bill_number = str_extract(bill_id, "[0-9]+$"),
    bill_number = glue("{bill_type}{bill_number}")
  ) |>
  select(UUID, session, bill_number)

master |>
  filter(!(UUID %in% list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/massachusetts"))) |>
  future_pmap(scrape_text)
