##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Scrape TX Bill Data
## Date: February 2025
## Author: Joe Loffredo
##################################################

library(tidyverse)
library(jsonlite)
library(glue)
library(rvest)
library(threadr)
library(janitor)

rm(list = ls())
gc()

OUTPUT_PATH <- 'TX/output'

# Functions ---------------------------------------------------------------
# Format bill base URL
build_url <- function(session, bill_number){
  # Transform bill number to match URL format
  bill_id <- str_remove_all(bill_number, "\\s")
 
  glue('https://capitol.texas.gov/BillLookup/History.aspx?LegSess={session}&Bill={bill_id}')
}

# Get bill metadata
get_bill_metadata <- function(UUID, session, bill_number, state_url, page){
  # Get metadata values
  title <- page |> html_elements('#cellCaptionText') |> html_text()
  description <- page |> html_elements('#cellSubjects') |> html_text() |> str_squish()
  status <- page |> html_elements('#cellLastAction') |> html_text()
  
  # Fix status
  status <- status |> str_remove_all("^[0-9]{2}/[0-9]{2}/[0-9]{4}") |> str_trim()
  status <- ifelse(str_detect(status, "Effective on"), glue("Enacted - {status}"), status)
  
  tibble(
    uuid = UUID, 
    state = 'TX', 
    session = session, 
    state_bill_id = bill_number, 
    title = title, 
    description = description, 
    status = status, 
    state_url = state_url
  ) |> as.list() |> toJSON(auto_unbox = T, pretty = T) |> writeLines(glue("{OUTPUT_PATH}/bill_metadata/{UUID}.json"))
}

# Get bill sponsors
get_bill_sponsors <- function(UUID, session, bill_number, page){
  # Function to clean and split text
  clean_split <- function(text) {
    str_split(text, "\\| ", simplify = TRUE) |> sapply(str_trim, side = "both")
  }
  
  # Scrape and clean authors, sponsors, and cosponsors
  authors <- clean_split(page |> html_elements("#cellAuthors") |> html_text())
  coauthors <- clean_split(page |> html_elements("#cellCoauthors") |> html_text())
  sponsors <- clean_split(page |> html_elements("#cellSponsors") |> html_text())
  cosponsors <- clean_split(page |> html_elements("#cellCosponsors") |> html_text())
  
  # Trim to what I care about
  sponsors <- c(authors, sponsors) |> as_vector()
  cosponsors <- c(coauthors, cosponsors) |> as_vector()
  
  tibble(
    uuid = UUID, 
    state = 'TX', 
    session = session, 
    state_bill_id = bill_number, 
    sponsor_name = c(sponsors, cosponsors),
    sponsor_type = c(rep('sponsor', length(sponsors)), rep('cosponsor', length(cosponsors)))
  ) |> 
    group_by(uuid, state, session, state_bill_id) |>
    nest(sponsors = c(sponsor_name, sponsor_type)) |>
    ungroup() |>
    as.list() |>
    toJSON(pretty = T,auto_unbox = T) |> 
    writeLines(glue("{OUTPUT_PATH}/sponsors/{UUID}.json"))
  
}

get_bill_history <- function(UUID, session, bill_number, page){
  # Scrape bill history page
  bill_history <- page |> 
    html_node("table[frame='hsides'][rules='rows']") |> 
    html_table(fill = TRUE) |>
    row_to_names(row_number = 1) |>
    clean_names() |>
    mutate(
      journal_page = as.integer(journal_page),
      date = mdy(date),
      action = ifelse(
        !is.na(journal_page),
        glue("{description}: {description_2} {comment} (journal pg: {journal_page})") |> str_squish(),
        glue("{description}: {description_2}") |> str_squish()
      )
    ) |>
    select(date, action)
  
  tibble(
    uuid = UUID, 
    state = 'TX', 
    session = session, 
    state_bill_id = bill_number, 
    date = bill_history$date,
    action = bill_history$action
  ) |> 
    group_by(uuid, state, session, state_bill_id) |>
    nest(history = c(date, action)) |>
    ungroup() |>
    as.list() |>
    toJSON(pretty = T,auto_unbox = T) |> 
    writeLines(glue("{OUTPUT_PATH}/bill_history/{UUID}.json"))
}

scrape_bill <- function(UUID, session = NA, bill_number = NA){
  year <- str_extract(UUID, "[0-9]{4}")
  
  if(is.na(session)){
    session <- case_match(
      year,
      "2008" ~ "80R",
      "2007" ~ "80R",
      "2006" ~ "79R",
      "2005" ~ "79R",
      "2004" ~ "78R",
      "2003" ~ "78R",
      "2002" ~ "77R",
      "2001" ~ "77R",
      "2000" ~ "76R",
      "1999" ~ "76R",
      "1998" ~ "75R",
      "1997" ~ "75R",
      "1996" ~ "74R",
      "1995" ~ "74R"
    )
  }
  
  if(is.na(bill_number)){
    bill_number <- str_remove_all(UUID, "^TX[0-9]{4}")
    bill_number <- case_when(
      str_detect(bill_number, "^S[0-9]") ~ glue("SB {str_remove(bill_number, 'S')}"),
      str_detect(bill_number, "^H[0-9]") ~ glue("HB {str_remove(bill_number, 'H')}"),
      TRUE ~ glue("{str_extract(bill_number, '^[A-Z]+')} {str_extract(bill_number, '[0-9]+')}")
    ) 
  }
  
  state_url <- build_url(session, bill_number)
  page <- read_html(state_url)
  
  get_bill_metadata(UUID, session, bill_number, state_url, page)
  get_bill_sponsors(UUID, session, bill_number, page)
  get_bill_history(UUID, session, bill_number, page)
}
