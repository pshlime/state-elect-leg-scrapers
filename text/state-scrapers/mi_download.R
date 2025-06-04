##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Download MI Text
## Date: June 2025
## Author: Joe Loffredo
##################################################

rm(list = ls())
gc()

library(tidyverse)
library(rvest)
library(glue)
library(furrr)
library(fs)

plan(multisession, workers = 11)

build_url <- function(session, bill_number){
  glue('https://www.legislature.mi.gov/Bills/Bill?ObjectName={session}-{bill_number}')
}

scrape_text <- function(UUID, session, bill_number){
  message(UUID)
  TEXT_OUTPUT_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/michigan'
  
  url <- build_url(session, bill_number)
  response <- httr::GET(url, config = httr::config(ssl_verifypeer = FALSE))
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
      str_subset(".htm$") |>
      str_subset("/bill") |>
      str_subset("analysis", negate = T)
    
    if(!is_empty(text_links)){
      dir_create(glue("{TEXT_OUTPUT_PATH}/{UUID}"))
      
      text_links <- glue("https://www.legislature.mi.gov{text_links}")
      
      version_number <- 1 
      for(link in text_links) {
        text <- read_html(link) |> html_nodes("body") |> as.character() |> str_squish() |> str_trim()
        
        file_name <- basename(link) |> str_remove(".htm")
        file_name <- glue("{file_name}_v{version_number}.txt")

        write_lines(text, glue("{TEXT_OUTPUT_PATH}/{UUID}/{file_name}"))
        
        version_number <- version_number + 1
      }
    }
  }
}

vrleg_master_file <- readRDS("~/Desktop/GitHub/election-roll-call/bills/vrleg_master_file.rds")
master <- vrleg_master_file |> 
  filter(STATE == 'MI' & YEAR %in% c(1995:2014)) |>
  mutate(
    bill_id = str_remove_all(UUID, "MI"),
    year = str_extract(bill_id, "^[0-9]{4}"),
    bill_type = str_extract(bill_id, "[A-Z]+"),
    bill_type = case_match(
      bill_type,
      "H" ~ "HB",
      "S" ~ "SB",
      .default = bill_type
    ),
    bill_number = str_extract(bill_id, "[0-9]+$"),
    bill_number = str_pad(bill_number, width = 4, side = "left", pad = "0"),
    bill_number = glue("{bill_type}-{bill_number}")
  ) |>
  select(UUID, session = year, bill_number)

master |>
  future_pmap(scrape_text)


bill_text_files <- data.frame(
  file_path = list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/michigan", pattern = "*.txt", full.names = TRUE, recursive = TRUE)) |>
  mutate(
    file_name = basename(file_path),
    UUID = str_remove(file_path, file_name) |> basename()) |>
  select(UUID, file_path) |>
  write_csv("text/state-scrapers/mi_bill_text_files.csv")

#bill_text_files <- data.frame(
#  file_path = list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/michigan", pattern = "*.txt", full.names = TRUE, recursive = TRUE)) |>
#  filter(!str_detect(file_path, "processed|MI2014|MI2013|MI2012|MI2011")) |>
#  mutate(
#    file_name = basename(file_path),
#    UUID = str_remove(file_path, file_name) |> basename(),
#    # Extract version number from filename
#    version = str_extract(file_name, "v(\\d+)") |> str_remove("v") |> as.numeric()
#  ) |>
#  # Keep only the row with maximum version for each UUID
#  group_by(UUID) |>
#  slice_max(version, n = 1, with_ties = FALSE) |>
#  ungroup() |>
#  select(UUID, file_path) |>
#  write_csv("text/state-scrapers/mi_bill_text_files.csv")


