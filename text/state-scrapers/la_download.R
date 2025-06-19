##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Download LA Text
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

build_url <- function(session, bill_number){
  glue("https://legis.la.gov/legis/BillInfo.aspx?s={session}&b={bill_number}")
}

scrape_text <- function(UUID, session, bill_number){
  message(UUID)
  TEXT_OUTPUT_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/louisiana'
  
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
    
    text_landing <- page |> html_element('.ctl00_PageBody_MenuDocuments_3') |> html_attr('href')
    text_landing <- glue("https://legis.la.gov/legis/{text_landing}")  

    text_links <- read_html(text_landing) |> html_nodes("a") |> html_attr("href")
    text_links <- glue("https://legis.la.gov/legis/{text_links}")
    
    lapply(text_links, function(link) {
      file_name <- basename(link) |> str_remove_all("ViewDocument.aspx\\?d=")
      file_path <- glue("{TEXT_OUTPUT_PATH}/{UUID}/{file_name}.pdf")
      download.file(link, file_path, mode = "wb")
    })
  }
}

vrleg_master_file <- readRDS("~/Desktop/GitHub/election-roll-call/bills/vrleg_master_file.rds")
master <- vrleg_master_file |> 
  filter(STATE == 'LA' & YEAR %in% c(1995:2014)) |>
  mutate(
    bill_id = str_remove_all(UUID, "LA"),
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
      year == '2000' ~ '00RS',
      year == '2001' ~ '01RS',
      year == '2002' ~ '02RS',
      year == '2003' ~ '03RS',
      year == '2004' ~ '04RS',
      year == '2005' ~ '05RS',
      year == '2006' ~ '06RS',
      year == '2007' ~ '07RS',
      year == '2008' ~ '08RS',
      year == '2009' ~ '09RS',
      year == '2010' ~ '10RS',
      year == '2011' ~ '11RS',
      year == '2012' ~ '12RS',
      year == '2013' ~ '13RS',
      year == '2014' ~ '14RS'
    ),
    bill_number = glue("{bill_type}{bill_number}")
  ) |>
  select(UUID, session, bill_number)

master |>
  filter(!(UUID %in% list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/louisiana"))) |>
  future_pmap(scrape_text)

bill_text_files <- data.frame(
  file_path = list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/louisiana", pattern = "*.pdf", full.names = TRUE, recursive = TRUE)) |>
  mutate(
    file_name = basename(file_path),
    UUID = str_remove(file_path, file_name) |> basename()) |>
  select(UUID, file_path) |>
  write_csv("text/state-scrapers/la_bill_text_files.csv")
