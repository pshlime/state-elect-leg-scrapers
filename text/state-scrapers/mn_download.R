##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Download MN Text
## Date: June 2025
## Author: Joe Loffredo
##################################################

rm(list = ls())
gc()

library(tidyverse)
library(rvest)
library(glue)
library(fs)

clean_html <- function(html_content){
  # Ensure html_content is a single string by collapsing if it's a vector
  if(length(html_content) > 1) {
    html_content <- paste(html_content, collapse = "\n")
  }
  
  html_content <- str_replace_all(html_content, "<s>", '<strike class="amendmentDeletedText">')
  html_content <- str_replace_all(html_content, "</s>", "</strike>")
  html_content <- str_replace_all(html_content, '<u>', '<u class="amendmentInsertedText">')
  
  html_content <- str_replace_all(html_content, "\\n\\s*\\d+\\.\\d+\\s+", "\n")
  html_content <- str_replace_all(html_content, '<p[^>]*>', "")
  
  return(html_content)
  
}

build_url <- function(session, chamber, bill_number){
  glue('https://www.revisor.mn.gov/bills/bill.php?b={chamber}&f={bill_number}&ssn=0&y={session}')
}

scrape_text <- function(UUID, session, chamber, bill_number){
  message(UUID)
  TEXT_OUTPUT_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/minnesota'
  
  url <- build_url(session, chamber, bill_number)
  response <- httr::GET(url, config = httr::config(ssl_verifypeer = FALSE))
  if(response$status_code != 200){
    message(url)
    message(glue("Failed to fetch {UUID} - status code: {response$status_code}"))
    return(NULL)
  } else{
    page_text <- httr::content(response, "text")
    page <- read_html(page_text)
    
    text_link <- page |> 
      html_nodes("#legContainerMain .container a") |> 
      html_attr("href") |> 
      str_subset("bills/text|text.php?")
    
    if(!is_empty(text_link)){
      dir_create(glue("{TEXT_OUTPUT_PATH}/{UUID}"))
      
      text_link <- text_link[1]
      if(!str_detect(text_link,"bills/text")){
        text_link <- glue("https://www.revisor.mn.gov/bills/{text_link}")
      } else{
        text_link <- glue("https://www.revisor.mn.gov{text_link}")
      }

      if(session %in% c('2001','2002','2003','2004')){
        text <- read_html(text_link) |> html_nodes("pre") |> as.character() |> clean_html() |> str_trim() |> str_squish()
        
        # extract file name components
        number <- str_extract(text_link, "(?<=number=)[^&]+")
        type <- str_extract(text_link, "(?<=type=)[^&]+") 
        year <- str_extract(text_link, "(?<=session_year=)[^&]+")
        file_name <- glue("{number}_{type}_{year}_html.txt")
        
        write_lines(text, glue("{TEXT_OUTPUT_PATH}/{UUID}/{file_name}"))
      } else{
        rtf_file <- read_html(text_link) |> html_nodes("a") |> html_attr("href") |> str_subset("rtf")
        rtf_file <- glue("https://www.revisor.mn.gov{rtf_file}")
        
        # extract file name components
        number <- str_extract(text_link, "(?<=number=)[^&]+")
        type <- str_extract(text_link, "(?<=type=)[^&]+") 
        year <- str_extract(text_link, "(?<=session_year=)[^&]+")
        
        file_name <- glue("{number}_{type}_{year}")
        dest_file_path <- glue("{TEXT_OUTPUT_PATH}/{UUID}/{file_name}.rtf")
        download.file(rtf_file, destfile = dest_file_path, mode = "wb")
      }
    }
  }
  
  message(glue("Finished scraping {UUID} - {session} {chamber} {bill_number}"))
}

vrleg_master_file <- readRDS("~/Desktop/GitHub/election-roll-call/bills/vrleg_master_file.rds")
master <- vrleg_master_file |> 
  filter(STATE == 'MN' & YEAR %in% c(1995:2014)) |>
  mutate(
    bill_id = str_remove_all(UUID, "MN"),
    year = str_extract(bill_id, "^[0-9]{4}"),
    bill_type = str_extract(bill_id, "[A-Z]+"),
    bill_type = case_match(
      bill_type,
      "H" ~ "HF",
      "S" ~ "SF",
      .default = bill_type
    ),
    bill_number = str_extract(bill_id, "[0-9]+$"),
    bill_number = str_pad(bill_number, width = 4, side = "left", pad = "0"),
    bill_number = glue("{bill_type}{bill_number}"),
    chamber = ifelse(str_detect(bill_type,"^H"), "House", "Senate")
  ) |>
  filter(bill_type != "NULL") |>
  select(UUID, session = year, chamber, bill_number)

master |>
  filter(!(UUID %in% list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/minnesota"))) |>
  pmap(scrape_text)

bill_text_files <- data.frame(
  file_path = list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/minnesota", pattern = "*.rtf", full.names = TRUE, recursive = TRUE)) |>
  mutate(
    file_name = basename(file_path),
    UUID = str_remove(file_path, file_name) |> basename()) |>
  select(UUID, file_path) |>
  write_csv("text/state-scrapers/mn_bill_text_files.csv")
