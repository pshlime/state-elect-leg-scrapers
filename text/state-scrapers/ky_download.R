##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Download KY Text
## Date: May 2025
## Author: Joe Loffredo
##################################################

rm(list = ls())
gc()

library(tidyverse)
library(rvest)
library(glue)
library(fs)

convert_doc_to_pdf <- function(doc_path) {
  if (!file.exists(doc_path)) stop("File does not exist: ", doc_path)
  if (!grepl("\\.doc$", doc_path, ignore.case = TRUE)) stop("Input file must be a .doc file")
  
  soffice_path <- "/Applications/LibreOffice.app/Contents/MacOS/soffice"
  if (!file.exists(soffice_path)) stop("LibreOffice not found at expected path. Is it installed?")
  
  out_dir <- dirname(doc_path)
  
  cmd <- c(
    "--headless",
    "--convert-to", "pdf",
    "--outdir", shQuote(out_dir),
    shQuote(doc_path)
  )
  
  result <- system2(soffice_path, args = cmd, wait = TRUE)
  
  pdf_path <- sub("\\.doc$", ".pdf", doc_path, ignore.case = TRUE)
  
  # Wait briefly to ensure output file is written
  for (i in 1:10) {
    if (file.exists(pdf_path)) break
    Sys.sleep(0.5)
  }
  
  if (!file.exists(pdf_path)) stop("PDF not created. Conversion may have failed.")
  message("PDF saved to: ", pdf_path)
  return(invisible(pdf_path))
}

build_url <- function(session, bill_number){
  if(session %in% c('08rs', '09rs', '10rs', '11rs', '12rs', '13rs', '14rs')){
    glue("https://apps.legislature.ky.gov/record/{session}/{bill_number}.html")
  } else{
    glue("https://apps.legislature.ky.gov/record/{session}/{bill_number}.htm")
  }
}

scrape_text <- function(UUID, session, bill_number){
  message(UUID)
  TEXT_OUTPUT_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/kentucky'
  
  url <- build_url(session, bill_number)
  
  response <- httr::GET(url, config = httr::config(ssl_verifypeer = FALSE))
  if(response$status_code != 200){
    message(glue("Failed to fetch {UUID} - status code: {response$status_code}"))
    return(NULL)
  } else{
    page_text <- httr::content(response, "text")
    page <- read_html(page_text)
    text_links <- page |>
      html_nodes("a") |> 
      html_attr("href") |>
      str_subset(".doc") |>
      str_subset("LM\\.",negate = T)
    
    file_names <- text_links |> str_remove_all(glue('^https://apps.legislature.ky.gov/record/')) |> str_replace_all("/","_")
    text_links <- if_else(str_detect(text_links, "^https?://"), text_links, glue("https://apps.legislature.ky.gov/record/{session}/{text_links}"))
      
    lapply(seq_along(text_links), function(i) {
      tryCatch({
        dir_create(glue("{TEXT_OUTPUT_PATH}/{UUID}"))
        # Create a filename based on the UUID and link
        filename <- glue("{TEXT_OUTPUT_PATH}/{UUID}/{UUID}_{file_names[i]}")
        # Download the file
        download.file(text_links[i], filename, mode = "wb")
        
      }, error = function(e) {
        message(glue("Error scraping {text_links[i]}: {e$message}"))
      })
    })
    
    lapply(list.files(glue("{TEXT_OUTPUT_PATH}/{UUID}"), full.names = T), convert_doc_to_pdf)
  }
}

vrleg_master_file <- readRDS("~/Desktop/GitHub/election-roll-call/bills/vrleg_master_file.rds")
master <- vrleg_master_file |> 
  filter(STATE == 'KY' & YEAR %in% c(1995:2014)) |>
  mutate(
    bill_id = str_remove_all(UUID, "KY"),
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
      year == '2001' ~ '01rs',
      year == '2002' ~ '02rs',
      year == '2003' ~ '03rs',
      year == '2004' ~ '04rs',
      year == '2005' ~ '05rs',
      year == '2006' ~ '06rs',
      year == '2007' ~ '07rs',
      year == '2008' ~ '08rs',
      year == '2009' ~ '09rs',
      year == '2010' ~ '10rs',
      year == '2011' ~ '11rs',
      year == '2012' ~ '12rs',
      year == '2013' ~ '13rs',
      year == '2014' ~ '14rs',
    ),
    bill_number = glue("{bill_type}{bill_number}") |> str_to_lower()
  ) |>
  select(UUID, session, bill_number)

master |>
  filter(!(UUID %in% list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/kentucky"))) |>
  pmap(scrape_text)

bill_text_files <- data.frame(
  file_path = list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/kentucky", pattern = "*.pdf", full.names = TRUE, recursive = TRUE)) |>
  mutate(
    file_name = basename(file_path),
    UUID = str_extract(file_name, "^[^_]+")) |>
  select(UUID, file_path) |>
  filter(str_detect(file_path, "_bill\\.")) |>
  write_csv("text/state-scrapers/ky_bill_text_files.csv")
