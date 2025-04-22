##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Scrape FL
## Date: April 2025
## Author: Joe Loffredo
##################################################

library(tidyverse)
library(jsonlite)
library(glue)
library(httr)
library(xml2)
library(rvest)
library(pdftools)
library(tesseract)
library(janitor)
library(fs)

rm(list = ls())
gc()

OUTPUT_PATH <- 'FL/output'

# Functions
clean_html <- function(html_content) {
  html_content <- str_replace_all(html_content, "<p[^>]*>", " ")
  html_content <- str_replace_all(html_content, "</p>", " ")
  html_content <- str_replace_all(html_content, "<div[^>]*>", " ")
  html_content <- str_replace_all(html_content, "</div>", " ")
  html_content <- str_replace_all(html_content, "<a[^>]*>", " ")
  html_content <- str_replace_all(html_content, "</a>", " ")
  html_content <- str_replace_all(html_content, "<span[^>]*>", " ")
  html_content <- str_replace_all(html_content, "</span>", " ")
  html_content <- str_replace_all(html_content, "<b[^>]*>", " ")
  html_content <- str_replace_all(html_content, "</b>", " ")
  html_content <- str_replace_all(html_content, "<i[^>]*>", " ")
  html_content <- str_replace_all(html_content, "</i>", " ")
  html_content <- str_replace_all(html_content, "<td[^>]*>", " ")
  html_content <- str_replace_all(html_content, "<meta[^>]*>", " ")
  html_content <- str_replace_all(html_content, "</td>", " ")
  html_content <- str_replace_all(html_content, "</tr>", " ")
  html_content <- str_replace_all(html_content, "<tr[^>]*>", " ")
  html_content <- str_replace_all(html_content, "\\s+", " ")
  html_content <- str_replace_all(html_content, "<center[^>]*>", " ")
  html_content <- str_replace_all(html_content, "</center[^>]*>", " ")
  html_content <- str_replace_all(html_content, "<table[^>]*>", " ")
  html_content <- str_replace_all(html_content, "</table[^>]*>", " ")
  html_content <- str_replace_all(html_content, "\\[", " ")
  html_content <- str_replace_all(html_content, "\\]", " ")
  html_content <- str_replace_all(html_content, "</u> <u>", " ")
  html_content <- str_replace_all(html_content, "</u><u>", " ")
  html_content <- str_replace_all(html_content, '<u>', '<u class="amendmentInsertedText">')
  html_content <- str_replace_all(html_content, '<u class=\"Insert\">', '<u class="amendmentInsertedText">')
  html_content <- str_replace_all(html_content, '<s>', '<strike class="amendmentDeletedText">')
  html_content <- str_replace_all(html_content, '<s class="Remove">', '<strike class="amendmentDeletedText">')
  html_content <- str_replace_all(html_content, '</s>', '</strike>')
  html_content <- str_replace_all(html_content, '</pre>', ' ')
  html_content <- str_replace_all(html_content, "</font>","")
  html_content <- str_replace_all(html_content, "<font[^>]*>", "")
  html_content <- str_replace_all(html_content, "</page>", "")
  
  html_content <- str_trim(html_content)
  return(html_content)
}

build_url <- function(session, bill_number){
  # Pull just number
  bill_number <- str_extract(bill_number, "\\d+")
  glue("https://www.flsenate.gov/Session/Bill/{session}/{bill_number}")
}


get_bill_metadata <- function(UUID, session, bill_number, state_url, state_html){
  title <- state_html |> html_nodes("h2") |> html_text() |> str_squish() |> tail(1)
  description <- state_html |> html_nodes(".width80") |> html_text() |> str_squish()
  status <- state_html |> 
    html_nodes(".pad-left0") |> 
    html_text() |> 
    str_extract("Last Action:[^|]+") |> 
    str_trim() |>
    str_squish() |>
    str_replace_all("Last Action: [0-9]{1,2}/[0-9]{1,2}/[0-9]{2,4}", "") |>
    str_replace_all("Bill Text: Web Page", "") |>
    str_trim()
  
  status <- ifelse(str_detect(status, "Chapter"), glue("Enacted - {status}"), status)
  
  tibble(
    uuid = UUID, 
    state = 'FL', 
    session = session, 
    state_bill_id = bill_number, 
    title = title,
    description = description,
    status = status,
    state_url = state_url
  ) |> as.list() |> toJSON(auto_unbox = T, pretty = T) |> writeLines(glue("{OUTPUT_PATH}/bill_metadata/{UUID}.json"))
}

get_sponsors <- function(UUID, session, bill_number, state_html){
  sponsors_list <- state_html |> html_node("h2+ p") |> html_text() |> str_trim() |> str_squish()
  sponsors_list <- str_split(sponsors_list, ";")[[1]]
  sponsors_list <- str_trim(sponsors_list)
  cosponsor_index <- which(str_detect(sponsors_list, "\\(CO-INTRODUCERS\\)"))
  
  if(!is_empty(cosponsor_index)){
    sponsors <- sponsors_list[1:(cosponsor_index - 1)] |>
      str_replace_all(c("GENERAL BILL by "="","LOCAL BILL by"="","JOINT RESOLUTION by"="")) |>
      str_trim()
    sponsors_df <- data.frame(sponsor_name = c(sponsors), sponsor_type = "sponsor")
    cosponsors <- sponsors_list[(cosponsor_index + 1):length(sponsors_list)] |>
      str_replace_all("\\(CO-INTRODUCERS\\)", "") |>
      str_trim()
    cosponsors_df <- data.frame(sponsor_name = c(cosponsors), sponsor_type = "cosponsor")
    
    sponsors_df <- bind_rows(sponsors_df, cosponsors_df)
  } else{
    sponsors <- sponsors_list |>
      str_replace_all(c("GENERAL BILL by "="","LOCAL BILL by"="","JOINT RESOLUTION by"="")) |>
      str_trim()
    sponsors_df <- data.frame(sponsor_name = c(sponsors), sponsor_type = "sponsor")
  }
  
  sponsors_df <- sponsors_df |> filter(!is.na(sponsor_name))
  
  tibble(
    uuid = UUID, 
    state = 'FL', 
    session = session, 
    state_bill_id = bill_number, 
    sponsor_name = sponsors_df$sponsor_name,
    sponsor_type = sponsors_df$sponsor_type
  ) |> 
    group_by(uuid, state, session, state_bill_id) |>
    nest(sponsors = c(sponsor_name, sponsor_type)) |>
    ungroup() |>
    as.list() |>
    toJSON(pretty = T,auto_unbox = T) |> 
    writeLines(glue("{OUTPUT_PATH}/sponsors/{UUID}.json"))
}

get_bill_history <- function(UUID, session, bill_number, state_html){
  history_df <- state_html |>
    html_node("#tabBodyBillHistory") |>
    html_table(fill = T) |>
    separate_rows(Action, sep = "\\r\\n") |>
    mutate(
      date = as_date(Date, format = "%m/%d/%Y"),
      Action = str_remove_all(Action, "• ") |> str_trim() |> str_squish(),
      action = glue("{Chamber} - {Action}"),
      action = str_replace_all(action, c("^Senate - "="S - ","House - "="H - ")),
      action = str_remove_all(action, "^ - ")
    ) |>
    select(date, action)
  
  tibble(
    uuid = UUID, 
    state = 'FL', 
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
    writeLines(glue("{OUTPUT_PATH}/bill_history/{UUID}.json"))
}

get_votes <- function(UUID, session, bill_number, state_html){
  # Check to see if any votes
  if(is_empty(state_html |> html_node("h4#Votes + table.tbl"))){
    return(NULL)
  } else{
    votes_df <- state_html |> html_node("h4#Votes + table.tbl") |> html_table(fill = TRUE)
    votes_df$rollcall_url <- state_html |> html_nodes("#Votes+ .tbl a") |> html_attr("href")
    votes_df$rollcall_url <- glue("https://www.flsenate.gov{votes_df$rollcall_url}")
    
    parse_rollcall <- function(file_url){
      if(str_detect(file_url, "html$|HTML$")){
        rollcall_html <- read_html(file_url) |> html_nodes("pre") |> html_text()
        if(is_empty(rollcall_html)){
          rollcall_html <- read_html(file_url)
          vote_data <- rollcall_html |> html_nodes("body > table:nth-child(5)") |> html_text()
          vote_pattern <- "(Y|N|-|EX|CH)\\s+([A-Za-z,\\.\\-]+)"
          vote_data <- (str_extract_all(vote_data, vote_pattern))[[1]]
          rollcall_html <- html_text(rollcall_html)
        } else{
          vote_pattern <- "(Y|N|-|EX|CH)\\s+([A-Za-z,\\.\\-]+)"
          vote_data <- (str_extract_all(rollcall_html, vote_pattern))[[1]]
        }
        # Get roll call responses
        
        vote_data <- data.frame(raw = vote_data) |>
          mutate(
            response = str_extract(raw, "^[A-Z\\-]{1,2}") |> str_trim() |>
              case_match(
                "Y" ~ "Yea",
                "N" ~ "Nay",
                "EX" ~ "Absent",
                .default = "NV"
              ),
            name = str_extract(raw, " [A-Za-z,\\.]+$") |> str_trim() |>
              str_remove_all("[0-9\\-]+$")
          ) |>
          select(name, response) |>
          filter(!(name %in% c("THE", "YES", "The", "Yes")) & !is.na(name))
        
        # Get question
        description <- case_when(
          str_detect(rollcall_html, "PASSAGE") & str_detect(rollcall_html, "R3") ~ "Third Reading Passage",
          str_detect(rollcall_html, "Reading Number .: 3") ~ "Third Reading Passage",
          str_detect(rollcall_html, "PASSAGE") & str_detect(rollcall_html, "R2") ~ "Second Reading Passage",
          str_detect(rollcall_html, "PASSAGE") & str_detect(rollcall_html, "R2") ~ "Second Reading Passage",
          str_detect(rollcall_html, "Floor Actions ..: Passage") ~ "Passage",
          str_detect(rollcall_html, "PASSAGE") ~ "Passage",
          TRUE ~ NA_character_
        ) 
        
        counts <- vote_data |> 
          summarise(
            yeas = sum(response == "Yea", na.rm = TRUE),
            nays = sum(response == "Nay", na.rm = TRUE),
            other = sum(!(response %in% c('Yea','Nay')), na.rm = TRUE)
          )
        
        return(list(description = description, vote_data = vote_data, counts = counts))
        
      } else if(str_detect(file_url, "pdf$|PDF$")){
        file_name <- basename(file_url)
        download_path <- glue("FL/output/scratch_files/{file_name}")
        download.file(file_url, download_path, mode = "wb")
        
        pdf_text <- pdf_text(download_path)
        
        # Get question
        description_pattern <- "(?:SB|SJR|HB|HJR)\\s+\\d+\\s+([A-Za-z\\s]+)"
        description <- str_match(pdf_text, description_pattern)
        description <- description |> 
          str_trim() |>
          str_remove_all("^(SB|SJR|HB|HJR)\\s+\\d+\\s*") |>
          str_remove_all("Yeas|Nays|Not Voting") |>
          str_squish() |>
          unique()
        
        # Get roll call responses
        vote_pattern <- "(Y|EX|N)\\s+([A-Za-z\\-]+(?:\\s+[A-Za-z\\-]+)*)(?:\\-\\d+)"
        vote_data <- (str_extract_all(pdf_text, vote_pattern))[[1]]
        vote_data <- data.frame(raw = vote_data) |>
          mutate(
            response = str_extract(raw, "^[A-Z]{1,2}") |> str_trim() |>
              case_match(
                "Y" ~ "Yea",
                "N" ~ "Nay",
                "EX" ~ "Absent",
                .default = "NV"
              ),
            name = str_extract(raw, " [A-Za-z0-9\\-\\s]+$") |> str_trim() |>
              str_remove_all("[0-9\\-]+$") |>
              str_remove_all("^President ")
          ) |>
          select(name, response) |>
          filter(!(name %in% c("THE", "YES", "The", "Yes")) & !is.na(name))
        
        counts <- vote_data |> 
          summarise(
            yeas = sum(response == "Yea", na.rm = TRUE),
            nays = sum(response == "Nay", na.rm = TRUE),
            other = sum(!(response %in% c('Yea','Nay')), na.rm = TRUE)
          )
        
        file_delete(dir_ls(glue("FL/output/scratch_files/")))
        
        return(list(description = description, vote_data = vote_data, counts = counts))
      }
    }
    
    votes_df$roll_call <- map(votes_df$rollcall_url, parse_rollcall)
    votes_df <- unnest_wider(votes_df, 'roll_call') |>
      unnest_wider('counts') |>
      mutate(
        uuid = UUID,
        state = 'FL',
        session = session,
        state_bill_id = bill_number,
        chamber = case_match(
          Chamber,
          "Senate" ~ "S",
          "House" ~ "H",
          .default = NA_character_),
        date = mdy_hm(Date) |> format("%Y-%m-%d")) |>
      select(uuid, state, session, state_bill_id, chamber, date, description, yeas, nays, other, roll_call = vote_data)
    
    for(i in 1:nrow(votes_df)){
      votes_df |>
        slice(i) |>
        as.list() |>
        toJSON(pretty = T, auto_unbox = T) |>
        writeLines(glue("{OUTPUT_PATH}/votes/{UUID}_{i}.json"))
    }
  }
}

get_bill_text <- function(UUID, state_html){
  bill_text_info <- state_html |> html_node("#tabBodyBillText") |> html_table(fill = T) |> 
    select(Version, Posted) |>
    clean_names() |>
    mutate(
      posted = mdy_hm(posted) |> format("%Y-%m-%d"),
      UUID = UUID) |>
      select(UUID, everything())
  
  bill_text_links <- state_html |> html_nodes("#tabBodyBillText .lnk_BillTextHTML") |> html_attr("href")
  bill_text_links <- glue("https://www.flsenate.gov{bill_text_links}")
  bill_text_info$text_url <- bill_text_links
  
  process_text <- function(UUID, version, posted, text_url){
    dir_create(glue("{OUTPUT_PATH}/bill_text/{UUID}"))
    
    download_path <- glue("{OUTPUT_PATH}/bill_text/{UUID}")
    raw_file_name <- str_c(version, posted, sep = "_") |> 
      str_replace_all(c("-"="_"," "="")) |> 
      str_c("_plain",".txt")
    html_file_name <- str_c(version, posted, sep = "_") |> 
      str_replace_all(c("-"="_"," "="")) |> 
      str_c("_html",".txt")
    
    download.file(text_url, glue("{download_path}/{raw_file_name}"), mode = "wb")
    
    text_html <- read_html(glue("{download_path}/{raw_file_name}"))
    
    raw_text <- text_html |> 
      html_nodes("pre") |> 
      html_text() |> 
      str_remove_all("\r\n\r\n[0-9\\s]{1,3}") |>
      str_remove_all("CODING: Words stricken are deletions; words underlined are additions.") |>
      str_trim() |> 
      str_squish()
    
    html_format <- text_html |> 
      html_nodes("pre") |> 
      as.character() |> 
      str_remove_all("<a name=\"Page[0-9]{1,3}Line\\d+\"></a>\\s*\\d+\\s*") |>
      str_remove_all("\r\n\r\n[0-9\\s]{1,3}") |>
      clean_html() |>
      str_remove_all("CODING: Words <strike class=\"amendmentDeletedText\">stricken</strike> are deletions; words <u class=\"amendmentInsertedText\">underlined</u> are additions.") |>
      str_trim() |> 
      str_squish()
    
    # Debugging logs
    message("Writing plain text file: ", raw_file_name)
    writeLines(raw_text, glue("{download_path}/{raw_file_name}"))
    
    message("Writing HTML format text file: ", html_file_name)
    writeLines(html_format, glue("{download_path}/{html_file_name}"))
  }
  
  pmap(bill_text_info, process_text)
}

scrape_bill <- function(UUID, session = NA, bill_number = NA){
  state_url <- build_url(session, bill_number)
  state_html <- read_html(state_url)
  
  get_bill_metadata(UUID, session, bill_number, state_url, state_html)
  get_sponsors(UUID, session, bill_number, state_html)
  get_bill_history(UUID, session, bill_number, state_html)
  get_votes(UUID, session, bill_number, state_html)
  get_bill_text(UUID, state_html)
}

# ## Testing
# session = '2007'
# UUID = 'FL2007H537'
# bill_number = 'HB537'
# scrape_bill(UUID, session, bill_number)
