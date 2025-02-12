##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Scrape TX Votes
## Date: February 2025
## Author: Joe Loffredo
##################################################

rm(list = ls())
gc()

library(tidyverse)
library(rvest)
library(glue)
library(threadr)
library(fs)
library(googlesheets4)
library(pdftools)
library(tesseract)
library(reticulate)

source_python("TX/code/parse_votes.py")

# Use state website to see all text versions
retrieve_vote_files <- function(session, bill_id){
  bill_id <- str_replace_all(bill_id, " ", "")
  url <- glue("https://capitol.texas.gov/BillLookup/Actions.aspx?LegSess={session}&Bill={bill_id}")
  
  # Retrieve the HTML
  html <- read_html(url)
  # Get the text links in html format
  journals <- html |> html_elements(".houvote , .senvote") |> html_attr("href") |> str_subset("journals")
  journals <- case_when(
    str_detect(journals,"hjrnl") ~ glue("ftp://ftp.legis.state.tx.us/journals/{session}/pdf/house/{basename(journals)}"),
    str_detect(journals,"sjrnl") ~ glue("ftp://ftp.legis.state.tx.us/journals/{session}/pdf/senate/{basename(journals)}"),
  )
  
  unique(journals)
}

# Download html files
download_vote_page <- function(UUID, session, file_path){
  VOTE_OUTPUT_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/previous_leg_files/TX'
  chamber <- str_extract(file_path, "house|senate")
  chamber <- ifelse(session == '82R', str_to_title(chamber), chamber)
  file_path <- ifelse(session == '82R', file_path |> str_replace("house", "House") |> str_replace("senate", "Senate"), file_path)
  
  dir_create(glue("{VOTE_OUTPUT_PATH}/{UUID}"))
  page_number <- basename(file_path) |> str_extract("#page=[0-9]+") |> str_remove("#page=") |> as.integer()
  
  file_name <- basename(file_path) |> str_remove_all(".PDF#page=[0-9]+")
  file_path <- file_path |> str_remove_all("#page=[0-9]+")
  # Create destination file name
  raw_dest_file <- glue("{VOTE_OUTPUT_PATH}/{UUID}/{file_name}.pdf")
  
  download_ftp_file(file_path, raw_dest_file)
  
  start_page <- ifelse(page_number > 10, page_number - 1 , 1)
  end_page <- page_number + 1
  
  text <- pdf_text(raw_dest_file) |> str_trim() |> str_replace_all('(  +)', " ")
  text <- text[c(1, start_page:end_page)] |> unique() |> str_c(collapse = " ")
  
  # Create destination file name
  processed_dest_file <- glue("{VOTE_OUTPUT_PATH}/{UUID}/{file_name}.txt")
  write(text, processed_dest_file)
  
  return(tibble(UUID = UUID, file_path = raw_dest_file, text = text, chamber = chamber))
}

scrape_text <- function(UUID){
  year <- str_extract(UUID, "[0-9]{4}")
  
  session <- case_match(
    year,
    "2012" ~ "82R",
    "2011" ~ "82R",
    "2010" ~ "81R",
    "2009" ~ "81R"
  )
  
  bill_number <- str_remove_all(UUID, "^TX[0-9]{4}")
  bill_number <- case_when(
    str_detect(bill_number, "^S[0-9]") ~ glue("SB {str_remove(bill_number, 'S')}"),
    str_detect(bill_number, "^H[0-9]") ~ glue("HB {str_remove(bill_number, 'H')}"),
    TRUE ~ glue("{str_extract(bill_number, '^[A-Z]+')} {str_extract(bill_number, '[0-9]+')}")
  ) 
  
  bill_number_full <- case_when(
    str_detect(bill_number, "SB") ~ glue("SENATE BILL {str_remove(bill_number, 'SB ')}"),
    str_detect(bill_number, "HB") ~ glue("HOUSE BILL {str_remove(bill_number, 'HB ')}"),
    str_detect(bill_number, "HJR") ~ glue("HOUSE JOINT RESOLUTION {str_remove(bill_number, 'HJR ')}"),
    str_detect(bill_number, "SJR") ~ glue("SENATE JOINT RESOLUTION {str_remove(bill_number, 'SJR ')}"),
    str_detect(bill_number, "HR") ~ glue("HOUSE RESOLUTION {str_remove(bill_number, 'HR ')}"),
    str_detect(bill_number, "SR") ~ glue("SENATE RESOLUTION {str_remove(bill_number, 'SR ')}"),
    str_detect(bill_number, "HCR") ~ glue("HOUSE CONCURRENT RESOLUTION {str_remove(bill_number, 'HCR ')}"),
    str_detect(bill_number, "SCR") ~ glue("SENATE CONCURRENT RESOLUTION {str_remove(bill_number, 'SCR ')}"),
    TRUE ~ bill_number
  )
  
  vote_files <- retrieve_vote_files(session, bill_number)
  if(!is_empty(vote_files)){
    print(glue("Processing {UUID}"))
    processed_text <- vote_files |> map(~ download_vote_page(UUID, session, .x)) |> bind_rows()
    parsed_votes <- processed_text |> 
      mutate(parsed = map(text, parse_rollcall, bill_number, bill_number_full)) |> 
      unnest_wider(parsed) |> 
      unnest_wider(response)
      
      test = parsed_votes |>
      mutate(
        uuid = UUID, 
        state = 'TX', 
        session = session, 
        state_bill_id = bill_number,
        chamber = case_match(chamber,"house" ~ "H","senate" ~ "S","House" ~ "H","Senate" ~ "S"),
        date = mdy(voteDate),
        description = voteQuestion,
        yeas = map_int(yea, ~sum(!is.na(.))),
        nays = map_int(nay, ~sum(!is.na(.))),
        other = map_int(present, ~sum(!is.na(.))) + map_int(absent, ~sum(!is.na(.)))
      )
  } else {
    print(glue("No votes found for {UUID}"))
    return(NULL)
  }
  
}

# Build list of UUIDs
vrleg_master_file <- readRDS("~/Desktop/GitHub/election-roll-call/bills/vrleg_master_file.rds")
tx_master <- vrleg_master_file |> filter(STATE == 'TX' & YEAR %in% c(2009:2012)) |> pull(UUID)

already_processed <- dir_ls('TX/output/votes/') |> basename()
bills_to_process <- c(gs_tx_list, tx_master) |> unique() |> setdiff(already_processed)

future_map(bills_to_process, scrape_text)
