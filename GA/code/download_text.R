##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Download GA files
## Date: May 2025
## Author: Joe Loffredo
##################################################

rm(list = ls())
gc()

library(tidyverse)
library(glue)
library(fs)
library(furrr)

plan(multisession, workers = 11)

ga_bill_links <- read_csv("GA/output/ga_bill_text_links.csv")

download_file <- function(uuid, text_url, text_version){
  message(uuid)
  TEXT_OUTPUT_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/georgia'
  
  dir_create(glue("{TEXT_OUTPUT_PATH}/{uuid}"))
  
  dest_file_path <- glue("{TEXT_OUTPUT_PATH}/{uuid}/{uuid}_{text_version}.pdf")
    
  tryCatch({
    download.file(text_url, dest_file_path, quiet = TRUE)
  }, error = function(e) {
    message(glue("Error downloading {text_url}: {e$message}"))
  })
  
  return(dest_file_path)
}

ga_bill_links <- ga_bill_links |> mutate(pdf_path = future_pmap_chr(list(uuid, text_url, text_version), download_file))

write_csv(ga_bill_links, 'GA/output/ga_bill_text_links.csv')
