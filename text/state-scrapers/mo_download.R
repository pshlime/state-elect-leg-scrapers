##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Download MO Text
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

mo_senate_links <- read_csv("text/state-scrapers/mo_senate_links.csv")

build_url <- function(chamber, session, bill_number){
  if(chamber == "H"){
    glue("https://house.mo.gov/BillContent.aspx?bill={bill_number}&year={session}&code=R&style=new")
  } else {
    session <- str_sub(session, 3, 4)
    
    mo_senate_links |>
      filter(session_id == session, bill_id == bill_number) |>
      pull(url)
  }
}

scrape_text <- function(UUID, chamber, session, bill_number){
  message(UUID)
  
  TEXT_OUTPUT_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/missouri'

  url <- build_url(chamber, session, bill_number)
  response <- httr::GET(url, config = httr::config(ssl_verifypeer = FALSE, followlocation = TRUE))
  
  if(response$status_code != 200){
    message(url)
    message(glue("Failed to fetch {UUID} - status code: {response$status_code}"))
    return(NULL)
  } else{
    page_text <- httr::content(response, "text")
    page <- read_html(page_text)
    
    if(chamber == 'H'){
      text_link <- page |> html_nodes("a") |> html_attr("href") |> str_subset("billspdf")
      
      if(!is_empty(text_link)){
        dir_create(glue("{TEXT_OUTPUT_PATH}/{UUID}"))
        text_link <- tail(text_link,1)
        
        file_name <- basename(text_link)
        download.file(text_link, destfile = glue("{TEXT_OUTPUT_PATH}/{UUID}/{file_name}"), mode = "wb")
      }
    } else{
      link <- page |> html_nodes("#hlFullBillText") |> html_attr("href")
      
      text_link <- read_html(link) |> html_nodes("a") |> html_attr("href") |> str_subset("pdf-bill")
      
      if(!is_empty(text_link)){
        dir_create(glue("{TEXT_OUTPUT_PATH}/{UUID}"))
        text_link <- tail(text_link,1)
        
        file_name <- basename(text_link)
        download.file(text_link, destfile = glue("{TEXT_OUTPUT_PATH}/{UUID}/{file_name}"), mode = "wb")
      }
    }
  }
}

vrleg_master_file <- readRDS("~/Desktop/GitHub/election-roll-call/bills/vrleg_master_file.rds")
master <- vrleg_master_file |> 
  filter(STATE == 'MO' & (YEAR %in% c(2004:2010) | YEAR %in% c(2011:2014) & is.na(ls_bill_id))) |>
  mutate(
    bill_id = str_remove_all(UUID, "MO"),
    year = str_extract(bill_id, "^[0-9]{4}"),
    bill_type = str_extract(bill_id, "[A-Z]+"),
    bill_type = case_match(
      bill_type,
      "H" ~ "HB",
      "S" ~ "SB",
      "SJRR" ~ "SJR",
      "HJRR" ~ "HJR",
      .default = bill_type
    ),
    bill_number = str_extract(bill_id, "[0-9]+$"),
    bill_number = glue("{bill_type}{bill_number}"),
    chamber = ifelse(str_detect(bill_type, "H"), "H", "S")
  ) |>
  select(UUID, chamber, session = year, bill_number)

master |>
  filter(!(UUID %in% list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/missouri"))) |>
  future_pmap(scrape_text, .progress = T)

bill_text_files <- data.frame(
  file_path = list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/missouri", pattern = "*.pdf", full.names = TRUE, recursive = TRUE)) |>
  mutate(
    file_name = basename(file_path),
    UUID = str_remove(file_path, file_name) |> basename()) |>
  select(UUID, file_path) |>
  write_csv("text/state-scrapers/mo_bill_text_files.csv")
