##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Scrape AZ Bill Text
## Date: May 2025
## Author: Joe Loffredo
##################################################

rm(list = ls())
gc()

library(tidyverse)
library(jsonlite)
library(rvest)
library(glue)
library(furrr)
library(fs)

plan(multisession, workers = 11)

retrieve_document_links <- function(document_id){
  document_list_url <- glue("https://apps.azleg.gov/api/DocType/?billStatusId={document_id}")
  
  document_listing <- read_json(document_list_url)
  document_listing <- map_dfr(document_listing, function(group) {
    map_dfr(group$Documents, function(doc) {
      tibble(
        DocumentGroupCode = group$DocumentGroupCode,
        DocumentGroupName = group$DocumentGroupName,
        Id = doc$Id,
        DocumentName = doc$DocumentName,
        PdfPath = doc$PdfPath,
        HtmlPath = doc$HtmlPath,
        WordPath = doc$WordPath,
        AmendSub = doc$AmendSub,
        ItemNum = doc$ItemNum
      )
    })
  }) |>
    filter(DocumentGroupName == 'Bill Versions') |>
    mutate(DocumentName = str_remove(DocumentName, " Version$")) |>
    select(version = DocumentName, link = HtmlPath)
  
 return(document_listing) 
}

scrape_text <- function(UUID, document_id){
  message(UUID)
  TEXT_OUTPUT_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/arizona'
  
  text_links <- tryCatch(
    retrieve_document_links(document_id),
    error = function(e) {
      message(glue("Error retrieving document links for {UUID}: {e$message}"))
      return(NULL)
    })
  
  if (is.null(text_links)) {
    return(NULL)
  } else{
    dir_create(glue("{TEXT_OUTPUT_PATH}/{UUID}"))
    
    text_links |>
      pmap(function(link, version) {
        page <- read_html(link)
        text <- page |> html_nodes("p") |> as.character() |> paste(collapse = "\n") |> str_trim() |> str_squish()
        
        file_name <- basename(link) |> str_remove(".htm")
        dest_file_path <- glue("{TEXT_OUTPUT_PATH}/{UUID}/{file_name}_{version}.txt")
        
        writeLines(text, dest_file_path)
      })
  }
  
  Sys.sleep(1)
}

bills <- list.files(path = "AZ/output/bill_metadata/", pattern = "*.json", full.names = TRUE) |>
  map_df(~ {
    json <- fromJSON(.x)
    # Remove NULL elements or replace with NA
    json[map_lgl(json, is.null)] <- NA
    as_tibble(json)
  })

bills |>
  mutate(document_id = basename(state_url) |> str_remove("\\?SessionId=[0-9]{1,3}$")) |>
  select(UUID = uuid, document_id) |>
  future_pmap(scrape_text)

bill_text_files <- data.frame(
  file_path = list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/arizona", pattern = "*.txt", full.names = TRUE, recursive = TRUE)) |>
  mutate(UUID = str_remove(file_path,basename(file_path)) |> basename()) |>
  select(UUID, file_path) |>
  write_csv("AZ/output/az_bill_text_files.csv")


