##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Retrieve NC bill links
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

build_url <- function(session, bill_id){
  glue("https://www.ncleg.gov/BillLookUp/{session}/{bill_id}")
}

retrieve_links <- function(url){
  page <- read_html(url)
  links <- page |> 
    html_nodes(".card-body a") |> 
    html_attr("href") |> 
    str_subset(".pdf")
  
  links <- glue("https://www.ncleg.gov{links}")
}

retrieve_text <- function(UUID, session, bill_id) {
  message(UUID)
  
  TEXT_OUTPUT_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/north_carolina'
  url <- build_url(session, bill_id)
  links <- retrieve_links(url)
  
  if (length(links) == 0) {
    return(NULL)
  } else {
    dir_create(glue("{TEXT_OUTPUT_PATH}/{UUID}"))
    
    dest_file_paths <- lapply(links, function(link) {
      file_name <- basename(link)
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
gs_nc_list <- googlesheets4::read_sheet('1LRM6Dqrh8i4B8_NyfHBd589IkIvBPYjTY4wt42Ri4Fo') |> janitor::clean_names()

gs_nc_list <- gs_nc_list |> 
  mutate(
    session = as.character(session),
    bill_type = str_extract(bill_number, "^[A-Z]+"),
    bill_number = str_extract(bill_number, "[0-9]+$"),
    bill_type = case_match(
      bill_type,
      "SB" ~ "S",
      "HB" ~ "H",
      .default = bill_type
    ),
    bill_id = glue("{bill_type}{bill_number}"),
    UUID = glue("NC{session}{bill_type}{bill_number}")
  ) |>
  select(UUID, session, bill_id)

nc_master <- vrleg_master_file |> 
  filter(STATE == 'NC' & YEAR %in% c(1995:2015)) |>
  mutate(
    bill_id = str_remove_all(UUID, "NC"),
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
  select(UUID, session, bill_id)
  

already_processed <- dir_ls('/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/north_carolina') |> basename()
bills_to_process <- bind_rows(gs_nc_list, nc_master) |> distinct() |> filter(!(UUID %in% already_processed))

bills_to_process <- bills_to_process |> mutate(pdf_path = future_pmap(list(UUID, session, bill_id), retrieve_text))
bills_to_process <- bills_to_process |> unnest_longer(pdf_path)

write_csv(bills_to_process, 'NC/nc_bill_text_files.csv')
