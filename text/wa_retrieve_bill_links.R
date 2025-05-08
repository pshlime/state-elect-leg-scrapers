##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Retrieve WA Text
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

# Functions
build_url <- function(session, bill_number){
  glue("https://app.leg.wa.gov/billsummary?BillNumber={bill_number}&Year={session}#rollCallPopup")
}

retrieve_links <- function(url){
  page <- read_html(url)
  page |> 
    html_elements('a[href*="lawfilesext"]') |> 
    html_attr("href") |> 
    str_subset(".pdf")
}

retrieve_text <- function(UUID, session, bill_number) {
  message(UUID)
  
  TEXT_OUTPUT_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/washington'
  url <- build_url(session, bill_number)
  links <- retrieve_links(url)
  
  if (length(links) == 0) {
    return(NULL)
  } else {
    dir_create(glue("{TEXT_OUTPUT_PATH}/{UUID}"))
    
    dest_file_paths <- lapply(links, function(link) {
      file_name <- basename(link) |> str_remove_all("#page=[0-9]+")
      dest_file_path <- glue("{TEXT_OUTPUT_PATH}/{UUID}/{file_name}")
      
      tryCatch({
        download.file(link, dest_file_path, quiet = TRUE)
      }, error = function(e) {
        message(glue("Error downloading {link}: {e$message}"))
      })
      
      return(dest_file_path)
    })
    
    return(dest_file_paths)
  }
}


# Build list of UUIDs
vrleg_master_file <- readRDS("~/Desktop/GitHub/election-roll-call/bills/vrleg_master_file.rds")
gs_wa_list <- googlesheets4::read_sheet('1jzW_WzyAAEFKxTGZeSmyIn9UQpXhHqsEb5zCBmni228') |> janitor::clean_names()

gs_wa_list <- gs_wa_list |> 
  mutate(
    session = as.character(year),
    bill_type = str_extract(bill_number, "^[A-Z]+"),
    bill_number = str_extract(bill_number, "[0-9]+$"),
    bill_type = case_match(
      bill_type,
      "SB" ~ "S",
      "HB" ~ "H",
      .default = bill_type
    ),
    bill_id = glue("{bill_type}{bill_number}"),
    UUID = glue("WA{session}{bill_type}{bill_number}")
  ) |>
  select(UUID, session, bill_number)

wa_master <- vrleg_master_file |> 
  filter(STATE == 'WA' & YEAR %in% c(1995:2015)) |>
  mutate(
    bill_id = str_remove_all(UUID, "WA"),
    session = str_extract(bill_id, "^[0-9]{4}"),
    bill_type = str_extract(bill_id, "[A-Z]+"),
    bill_number = str_extract(bill_id, "[0-9]+$"),
    bill_id = glue("{bill_type}{bill_number}"),
    session = case_when(
      session %in% c('2001','2002') ~ '2001',
      session %in% c('2003','2004') ~ '2003',
      session %in% c('2005','2006') ~ '2005',
      session %in% c('2007','2008') ~ '2007',
      session %in% c('2009','2010') ~ '2009',
      session %in% c('2011','2012') ~ '2011',
      session %in% c('2013','2014') ~ '2013',
      session %in% c('2015','2016') ~ '2015'
    )
  ) |>
  select(UUID, session, bill_number)


already_processed <- dir_ls('/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/washington') |> basename()
bills_to_process <- bind_rows(gs_wa_list, wa_master) |> distinct() |> filter(!(UUID %in% already_processed))

bills_to_process <- bills_to_process |> mutate(pdf_path = future_pmap(list(UUID, session, bill_number), retrieve_text))
bills_to_process <- bills_to_process |> unnest_longer(pdf_path)

write_csv(bills_to_process, 'text/wa_bill_text_files.csv')
