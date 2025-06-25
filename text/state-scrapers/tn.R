##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Download TN Text
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
library(pdftools)

plan(multisession, workers = 11)

build_url <- function(session, bill_number) {
  glue("https://wapp.capitol.tn.gov/apps/Billinfo/default.aspx?BillNumber={bill_number}&ga={session}")
}

scrape_text <- function(UUID, session, bill_number){
  message(UUID)
  
  TEXT_OUTPUT_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/tennessee'
  
  url <- build_url(session, bill_number)
  response <- httr::GET(url, config = httr::config(ssl_verifypeer = FALSE, followlocation = TRUE))
  
  if(response$status_code != 200){
    message(url)
    message(glue("Failed to fetch {UUID} - status code: {response$status_code}"))
    return(NULL)
  } else{
    page_text <- httr::content(response, "text")
    page <- read_html(page_text)
    
    short_summary <- page |> html_element("#lblAbstract") |> html_text() |> str_trim() |> str_squish()
    
    full_summary <- page |> html_elements('.billsummarycontent') |> html_text() |> str_flatten() |> str_trim() |> str_squish()
    
    text_links <- page |> 
      html_nodes("a") |> 
      html_attr("href") |> 
      str_subset("pdf") |>
      str_subset("Bill/") |>
      unique()
    
    if(!is_empty(text_links)){
      dir_create(glue("{TEXT_OUTPUT_PATH}/{UUID}"))
      
      lapply(text_links, function(link) {
        file_name <- basename(link)
        
        file_path <- glue("{TEXT_OUTPUT_PATH}/{UUID}/{file_name}")
        
        download.file(link, file_path)
        
        text <- pdf_text(file_path) |> str_flatten(collapse = '\n') |> str_trim() |> str_squish()
        
        output <- glue("Abstract: {short_summary}\n\nFull Summary: {full_summary}\n\nText: {text}")
        output_file <- glue("{TEXT_OUTPUT_PATH}/{UUID}/{file_name |> str_remove('pdf')}txt")
        write_lines(output, output_file)
      })
    }
  }
  
  Sys.sleep(3)
}

vrleg_master_file <- readRDS("~/Desktop/GitHub/election-roll-call/bills/vrleg_master_file.rds")
master <- vrleg_master_file |> 
  filter(STATE == 'TN'  & YEAR %in% c(2001:2024)) |>
  mutate(
    bill_id = str_remove_all(UUID, "TN"),
    year = str_extract(bill_id, "^[0-9]{4}"),
    session = case_when(
      year %in% c('2023', '2024') ~ '113',
      year %in% c('2021', '2022') ~ '112',
      year %in% c('2019', '2020') ~ '111',
      year %in% c('2017', '2018') ~ '110',
      year %in% c('2015', '2016') ~ '109',
      year %in% c('2013', '2014') ~ '108',
      year %in% c('2011', '2012') ~ '107',
      year %in% c('2009', '2010') ~ '106',
      year %in% c('2007', '2008') ~ '105',
      year %in% c('2005', '2006') ~ '104',
      year %in% c('2003', '2004') ~ '103',
      year %in% c('2001', '2002') ~ '102',
      TRUE ~ NA_character_
    ),
    bill_type = str_extract(bill_id, "[A-Z]+"),
    bill_type = case_match(
      bill_type,
      "H" ~ "HB",
      "S" ~ "SB",
      'SJRR' ~ "SJR",
      'HJRR' ~ "HJR",
      .default = bill_type
    ),
    bill_number = str_extract(bill_id, "[0-9]+$"),
    bill_number = str_pad(bill_number, width = 4, side = "left", pad = "0"),
    bill_number = glue("{bill_type}{bill_number}")
  ) |>
  select(UUID, session, bill_number) |>
  distinct()

master |>
  filter(!(UUID %in% list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/tennessee"))) |>
  future_pmap(scrape_text, .progress = T)
