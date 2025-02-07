##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Scrape CA from Open States
## Date: February 2025
## Author: Joe Loffredo
##################################################

library(tidyverse)
library(jsonlite)
library(glue)
library(rvest)

rm(list = ls())
gc()

OUTPUT_PATH <- 'CA/output'
ca_roll_call <- readRDS('~/Dropbox (MIT)/previous_leg_files/CA/ca_roll_call.rds')

# Functions ---------------------------------------------------------------
# Format bill base URL
build_url <- function(session, bill_number){
  # Transform session identifier to match URL format
  session_id <- case_match(session,
    '2007-2008' ~ '0708',
    '2005-2006' ~ '0506',
    '2003-2004' ~ '0304',
    '2001-2002' ~ '0102',
    '1999-2000' ~ '9900',
    '1997-1998' ~ '9798',
    '1995-1996' ~ '9596'
  )
  # Transform bill number to match URL format
  bill_id <- str_replace_all(bill_number, ' ', '_') |> str_to_lower()

  return(glue('http://leginfo.ca.gov/cgi-bin/postquery?bill_number={bill_id}&sess={session_id}'))
}

# Retrieve all available page links
get_page_links <- function(state_url){
  # Scrape main bill page
  page <- read_html(state_url)
  # Collect all hyperlinks
  page_links <- page |> html_nodes("a") |> html_attr("href")
  page_links <- glue("http://leginfo.ca.gov{page_links}")

  return(page_links)
}

# Get bill metadata
get_bill_metadata <- function(uuid, session, bill_number, state_url, page_links){
  # Scrape bill status page
  status_url <- page_links |> str_subset("_status")
  status_page_text <- read_html(status_url) |> html_text()
  
  title <- sub(".*TITLE\\t:\\s*(.*)\\n.*", "\\1", status_page_text)
  title <- gsub("[\n\t]", " ", title) |> str_trim() |> str_squish()
  
  lines <- str_split(status_page_text, "\n")[[1]]
  
  # Extract status
  last_hist_action_index <- grep("LAST HIST. ACTION", lines)
  status_lines <- lines[last_hist_action_index:length(lines)]
  ## Capture all lines until we find "TITLE"
  status_text <- status_lines[1]
  for (i in 2:length(status_lines)) {
    if (str_detect(status_lines[i], "TITLE")) break
    status_text <- str_c(status_text, " ", status_lines[i])
  }
  status <- str_remove(status_text, "^LAST HIST. ACTION") |> str_trim() |> str_squish() |> str_remove("^:") |> str_trim()
  status <- ifelse(str_detect(status, "Chaptered"), glue("Enacted - {status}"), status)
  
  # Extract topic
  topic_index <- grep("TOPIC", lines)
  topic_lines <- lines[topic_index:length(lines)]
  ## Capture all lines until we find "+LAST AMENDED"
  topic_text <- topic_lines[1]
  for (i in 2:length(topic_lines)) {
    if (str_detect(topic_lines[i], "LAST AMENDED")) break
    topic_text <- str_c(topic_text, " ", topic_lines[i])
  }
  topic <- str_remove(topic_text, "^TOPIC") |> str_trim() |> str_squish() |> str_remove("^:") |> str_trim()
  
  tibble(
    uuid = uuid, 
    state = 'CA', 
    session = session, 
    state_bill_id = bill_number, 
    title = title, 
    description = topic, 
    status = status, 
    state_url = state_url
  ) |> as.list() |> toJSON(auto_unbox = T, pretty = T) |> writeLines(glue("{OUTPUT_PATH}/bill_metadata/{uuid}.json"))
}

# Get bill sponsors
get_bill_sponsors <- function(uuid, session, bill_number, page_links){
  # Scrape bill status page
  status_url <- page_links |> str_subset("_status")
  status_page_text <- read_html(status_url) |> html_text()
  
  # Extract status using regex
  # Split the text into lines
  lines <- str_split(status_page_text, "\n")[[1]]
  authors_index <- grep("AUTHOR", lines)
  author_lines <- lines[authors_index:length(lines)]
  # Capture all lines until we find "TITLE"
  author_text <- author_lines[1]
  for (i in 2:length(author_lines)) {
    if (str_detect(author_lines[i], "TOPIC")) break
    author_text <- str_c(author_text, " ", author_lines[i])
  }
  authors <- str_remove(author_text, "^AUTHOR\\(S\\)\t:") |> str_trim() |> str_squish() |> str_remove("^:") |> str_trim()
  sponsors <- ifelse(
    str_detect(authors, "Principal coauthors"),
    str_extract_all(authors, "(?<=^|\\s)([A-Za-z]+)(?=\\s\\(Principal coauthors)")[[1]],
    str_extract_all(authors, "(?<=^|\\s)([A-Za-z]+)(?=\\s\\(Coauthors?)")[[1]]
  )
  
  cosponsors <- str_extract_all(authors, "(?<=\\(Coauthors?:?\\s)([^)]+)(?=\\))")[[1]]
  cosponsors <- paste(cosponsors,collapse = ",") |> str_remove_all("Senators: | and ") |> str_replace_all(", ",",") |> str_squish() |> str_split(",",simplify = T)
  
  tibble(
    uuid = uuid, 
    state = 'CA', 
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
    writeLines(glue("{OUTPUT_PATH}/sponsors/{uuid}.json"))
  
}

get_bill_history <- function(uuid, session, bill_number, page_links){
  # Scrape bill history page
  history_url <- page_links |> str_subset("_history")
  history_page_text <- read_html(history_url) |> html_text() |> str_remove_all("COMPLETE BILL HISTORY")
  
  # Extract the section after "BILL HISTORY"
  lines <- str_split(history_page_text, "\n")[[1]]
  history_index <- grep("BILL HISTORY", lines)
  history_lines <- lines[history_index:length(lines)]
  
  # Separate the date and action
  history_df <- data.frame(
    date = str_extract(history_lines, "^[A-Za-z\\.]+\\s+\\d{1,2}"),
    action = str_replace(history_lines, "^[A-Za-z]+\\s+\\d{1,2}\\s*", "")
  ) |>
    filter(action != 'BILL HISTORY') |>
    mutate(action = case_when(
      !is.na(date) ~ str_replace(action, date, "") |> str_trim() |> str_squish(),
      TRUE ~ action)
    ) |>
    mutate(action = if_else(is.na(date), lag(action, default = "") %>% paste(action, sep = " "), action)) |>
    fill(date) |>
    group_by(date) |>
    filter(nchar(action) == max(nchar(action), na.rm = TRUE)) |>
    ungroup() |>
    mutate(year = ifelse(is.na(date) & str_detect(action,"[0-9]{4}"), action, NA_character_) |> as.integer()) |> 
    fill(year) |>
    mutate(
      date = glue("{date}, {year}") |> mdy(),
      action = str_remove_all(action,"[\n\t]")) |>
    filter(!is.na(date)) |>
    select(-year)
  
  tibble(
    uuid = uuid, 
    state = 'CA', 
    session = session, 
    state_bill_id = bill_number, 
    date = history_df$date,
    action = history_df$action
  ) |> 
    group_by(uuid, state, session, state_bill_id) |>
    nest(history = c(date, action)) |>
    ungroup() |>
    as.list() |>
    toJSON(pretty = T,auto_unbox = T) |> 
    writeLines(glue("{OUTPUT_PATH}/bill_history/{uuid}.json"))
}

get_votes <- function(uuid, session, bill_number){
  # Retrieve votes
  output_votes <- ca_roll_call |> filter(session == !!session, state_bill_id == bill_number) |>
    mutate(uuid = uuid) |> 
    select(uuid, everything())
  
  if(nrow(output_votes) == 1){
    vote_date <- output_votes |> pull(date) |> as.character() |> str_replace_all("-","")
    output_votes |> as.list() |> toJSON(auto_unbox = T, pretty = T) |> writeLines(glue("{OUTPUT_PATH}/votes/{uuid}_{vote_date}.json"))
  } else if(nrow(output_votes) > 1) {
    for(i in 1:nrow(output_votes)){
      vote_date = output_votes[i,] |> pull(date) |> as.character() |> str_replace_all("-","")
      output_votes[i,] |> as.list() |> toJSON(auto_unbox = T, pretty = T) |> writeLines(glue("{OUTPUT_PATH}/votes/{uuid}_{vote_date}_{i}.json"))
    }
  }
}

scrape_bill <- function(UUID, session = NA, bill_number = NA){
  year <- str_extract(UUID, "[0-9]{4}")
  
  if(is.na(session)){
    session <- case_match(
      year,
      "2008" ~ "2007-2008",
      "2007" ~ "2007-2008",
      "2006" ~ "2005-2006",
      "2005" ~ "2005-2006",
      "2004" ~ "2003-2004",
      "2003" ~ "2003-2004",
      "2002" ~ "2001-2002",
      "2001" ~ "2001-2002",
      "2000" ~ "1999-2000",
      "1999" ~ "1999-2000",
      "1998" ~ "1997-1998",
      "1997" ~ "1997-1998",
      "1996" ~ "1995-1996",
      "1995" ~ "1995-1996"
    )
  }
  
  if(is.na(bill_number)){
    bill_number <- str_remove_all(UUID, "^CA[0-9]{4}")
    bill_number <- case_when(
      str_detect(bill_number, "^S[0-9]") ~ glue("SB {str_remove(bill_number, 'S')}"),
      str_detect(bill_number, "^A[0-9]") ~ glue("AB {str_remove(bill_number, 'A')}"),
      TRUE ~ glue("{str_extract(bill_number, '^[A-Z]+')} {str_extract(bill_number, '[0-9]+')}")
    ) 
  }
  
  state_url <- build_url(session, bill_number)
  page_links <- get_page_links(state_url)
  
  get_bill_metadata(UUID, session, bill_number, state_url, page_links)
  get_bill_sponsors(UUID, session, bill_number, page_links)
  get_bill_history(UUID, session, bill_number, page_links)
  get_votes(UUID, session, bill_number)
}
