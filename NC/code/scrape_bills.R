##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Scrape NC from Open States
## Date: January 2025
## Author: Joe Loffredo
##################################################

library(tidyverse)
library(jsonlite)
library(glue)
library(googlesheets4)
library(furrr)

rm(list = ls())
gc()

plan(multisession, workers = 11)

DROPBOX_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/previous_leg_files/NC'
OUTPUT_PATH <- 'NC/output'

# Wrangle OpenStates ------------------------------------------------------
#### Sponsors ####
sponsorships <- lapply(list.files(path = DROPBOX_PATH, pattern = "bill_sponsorships.csv", full.names = T, recursive = T), read_csv)
sponsorships_df <- do.call(bind_rows,sponsorships)

#### Bills ####
bills <- lapply(list.files(path = DROPBOX_PATH, pattern = "bills.csv",full.names = T, recursive = T), read_csv) 
bills_df <- do.call(bind_rows,bills)

#### Vote Counts ####
vote_counts <- lapply(list.files(path = DROPBOX_PATH, pattern = "vote_counts.csv",full.names = T, recursive = T), read.csv)
vote_counts_df <- do.call(rbind,vote_counts)

#### Vote Events ####
votes <- lapply(list.files(path = DROPBOX_PATH, pattern = "votes.csv",full.names = T, recursive = T), read.csv)
votes_df <- do.call(rbind,votes)

#### Bill Actions ####
bill_actions <- lapply(list.files(path = DROPBOX_PATH, pattern = "bill_actions.csv",full.names = T, recursive = T), read.csv)
bill_actions_df <- do.call(rbind,bill_actions)

#### Vote Roll Calls ####
vote_people <- lapply(list.files(path = DROPBOX_PATH, pattern = "vote_people.csv",full.names = T, recursive = T), read.csv)
vote_people_df <- do.call(rbind,vote_people)

# Clean lookup files ------------------------------------------------------
# State name --> state code
bills_df$jurisdiction <- state.abb[match(bills_df$jurisdiction,state.name)]

# Get most recent action and intro date
bill_actions_df$date <- lubridate::ymd(as.Date(bill_actions_df$date))
most_recent_action <- bill_actions_df |>
  group_by(bill_id) |>
  slice(which.min(order)) |>
  mutate(
    last_action_date = date,
    last_action_description = case_when(
      classification == "['became-law']" ~ glue("Enacted - {description}"),
      str_detect(description, "RATIFIED") ~ glue("Enacted - {description}"),
      str_detect(description, "^CH. SL") ~ glue("Enacted - {description}"),
      str_detect(description, "^CH. RES") ~ glue("Enacted - {description}"),
      TRUE ~ description
    )) |>
  select(bill_id, last_action_description, last_action_date) |>
  distinct()

intro_date <- bill_actions_df |> 
  group_by(bill_id) |>
  slice(which.max(order)) |>
  mutate(intro_year = year(date)) %>%
  select(bill_id, intro_date = date, intro_year)

bills_df <- bills_df |>
  left_join(most_recent_action, by = c("id"="bill_id")) |>
  left_join(intro_date, by = c("id"="bill_id")) |>
  rename(state = jurisdiction) |>
  mutate(
    bill_type = str_replace_all(identifier, "[0-9\\s]+$", ""),
    bill_type = str_to_upper(bill_type),
    bill_type = str_replace_all(
      bill_type,
      c("HB"='H','SB'='S','LB'='L','AB'='A',"HS"='H','HF'='H',
        'SF'='S','SS'='S','SD'='S','HD'='H',
        'HF'='H','SF'='S','HP'='H','SP'='S',
        'HRB'='H','SRB'='S','LD'='H')),
    bill_number = str_replace_all(identifier, "^[A-Z\\s]+",""),
    uuid = glue("{state}{intro_year}{bill_type}{bill_number}"),
    session_identifier = as.character(session_identifier),
    state_url = NA) |>
  rename(
    session = session_identifier,
    state_bill_id = identifier,
    description = subject,
    status = last_action_description,
  )

# Create dataframe for bill_metadata
bill_metadata <- bills_df |> select(uuid, state, session, state_bill_id, title, description, status, state_url)

# Create dataframe for sponsors
sponsors <- sponsorships_df |>
  left_join(bills_df, by = c("bill_id" = "id")) |>
  mutate(
    sponsor_type = case_when(
      classification.x == "primary" ~ "sponsor",
      primary == 'True' ~ "sponsor",
      classification.x == "cosponsor" ~ "cosponsor",
      TRUE ~ "sponsor"
    )
  ) |>
  rename(sponsor_name = name) |>
  select(uuid, state, session, state_bill_id, sponsor_name, sponsor_type) |>
  group_by(uuid, state, session, state_bill_id) |>
  nest(sponsors = c(sponsor_name, sponsor_type)) |>
  ungroup()

# Create dataframe for bill_history
bill_history <- bill_actions_df |>
  left_join(bills_df, by = c("bill_id" = "id")) |>
  mutate(
    chamber = case_when(
      organization_id == 'ocd-organization/6347dffa-4778-4dc0-97d7-fd4db3ff5328' ~ 'Senate',
      organization_id == 'ocd-organization/4861d484-9f30-411a-baaf-c2c12d4d174f' ~ 'House',
      TRUE ~ NA_character_
    ),
    action = glue("{chamber}: {description.x}")
  ) |>
  select(uuid, state, session, state_bill_id, date, action) |>
  group_by(uuid, state, session, state_bill_id) |>
  nest(history = c(date, action)) |>
  ungroup()

# Create dataframe for votes
votes <- votes_df |>
  left_join(bills_df |> select(id, state, state_bill_id, uuid, session), by = c("bill_id" = "id")) |>
  filter(session >= '2001') |>
  mutate(
    description = ifelse(str_detect(motion_classification, "passage"), glue("Passage - {motion_text}"), motion_text) |>
      str_replace_all("\\\\"," "),
    chamber = case_when(
      organization_id == 'ocd-organization/6347dffa-4778-4dc0-97d7-fd4db3ff5328' ~ 'S',
      organization_id == 'ocd-organization/4861d484-9f30-411a-baaf-c2c12d4d174f' ~ 'H',
      TRUE ~ NA_character_
    ),
    date = ymd(as_date(start_date))
  ) |>
  left_join(
    vote_counts_df |> 
      select(-id) |>
      mutate(
        option = case_match(
          option,
          "yes" ~ "yeas",
          "no" ~ "nays",
          .default = "other"
      )) |>
      pivot_wider(names_from = option, values_from = value,values_fn = sum),
    by = c("id" = "vote_event_id")) |>
  left_join(
    vote_people_df |> select(vote_event_id, response = option, name = voter_name),
    by = c("id" = "vote_event_id")) |>
  select(uuid, state, session, state_bill_id, chamber, date, description, yeas, nays, other, name, response) |>
  group_by(uuid, state, session, state_bill_id, chamber, date, description, yeas, nays, other) |>
  nest(roll_call = c(name, response)) |>
  ungroup()

rm(bill_actions, bill_actions_df, bills, bills_df, intro_date, most_recent_action, sponsorships, sponsorships_df, votes_df, vote_people, vote_people_df, vote_counts, vote_counts_df)

# Function to create output -----------------------------------------------
scrape_bill <- function(UUID){
  OUTPUT_PATH <- 'NC/output'
  # Save bill_metadata
  bill_metadata |> filter(uuid == UUID) |> as.list() |> toJSON(auto_unbox = T, pretty = T) |> writeLines(glue("{OUTPUT_PATH}/bill_metadata/{UUID}.json"))
  
  # Save sponsors
  sponsors |> filter(uuid == UUID) |> as.list() |> toJSON(auto_unbox = T, pretty = T) |> writeLines(glue("{OUTPUT_PATH}/sponsors/{UUID}.json"))
  
  # Save bill_history
  bill_history |> filter(uuid == UUID) |> as.list() |> toJSON(auto_unbox = T, pretty = T) |> writeLines(glue("{OUTPUT_PATH}/bill_history/{UUID}.json"))
  
  # Save votes
  output_votes <- votes |> filter(uuid == UUID)
  if(nrow(output_votes) == 1){
    vote_date <- output_votes |> pull(date) |> as.character() |> str_replace_all("-","")
    output_votes |> as.list() |> toJSON(auto_unbox = T, pretty = T) |> writeLines(glue("{OUTPUT_PATH}/votes/{UUID}_{vote_date}.json"))
  } else if(nrow(output_votes) > 1) {
    for(i in 1:nrow(output_votes)){
      vote_date = output_votes[i,] |> pull(date) |> as.character() |> str_replace_all("-","")
      output_votes[i,] |> as.list() |> toJSON(auto_unbox = T, pretty = T) |> writeLines(glue("{OUTPUT_PATH}/votes/{UUID}_{vote_date}_{i}.json"))
    }
  }
}

# Process bill list -------------------------------------------------------
vrleg_master_file <- readRDS("~/Desktop/GitHub/election-roll-call/bills/vrleg_master_file.rds")

gs_list <- googlesheets4::read_sheet('1LRM6Dqrh8i4B8_NyfHBd589IkIvBPYjTY4wt42Ri4Fo') |> janitor::clean_names()
gs_list <- gs_list |> 
  mutate(
    bill_number = str_replace(bill_number, "\\s",""),
    bill_type = str_extract(bill_number, "^[A-Z]+"),
    bill_number = str_extract(bill_number, "[0-9]+$"),
    bill_type_uuid = case_match(
      bill_type,
      "HB" ~ "H",
      "SB" ~ "S",
      .default = bill_type
    ),
    year = str_extract(session, "^[0-9]{4}"),
    session = str_remove(session, "^[0-9]{4}-"),
    UUID = glue("NC{year}{bill_type_uuid}{bill_number}"),
    bill_number = glue("{bill_type}{bill_number}")
  ) |>
  select(UUID, session, bill_number)

nc_master <- vrleg_master_file |> 
  filter(STATE == 'NC' & YEAR %in% c(1995:2014)) |>
  mutate(
    bill_id = str_remove_all(UUID, "NC"),
    session = str_extract(bill_id, "^[0-9]{4}"),
    bill_type = str_extract(bill_id, "[A-Z]+"),
    bill_type = case_match(
      bill_type,
      "H" ~ "HB",
      "S" ~ "SB",
      .default = bill_type
    ),
    bill_number = str_extract(bill_id, "[0-9]+$"),
    session = case_when(
      session %in% c('1995','1996') ~ '1995',
      session %in% c('1997','1998') ~ '1997',
      session %in% c('1999','2000') ~ '1999',
      session %in% c('1999','2000') ~ '2001',
      session %in% c('2001','2002') ~ '2001',
      session %in% c('2003','2004') ~ '2003',
      session %in% c('2005','2006') ~ '2005',
      session %in% c('2007','2008') ~ '2007',
      session %in% c('2009','2010') ~ '2009',
      session %in% c('2011','2012') ~ '2011',
      session %in% c('2013','2014') ~ '2013'
    ),
    bill_number = glue("{bill_type}{bill_number}")
  ) |>
  select(UUID, session, bill_number)

bills_to_process <- bind_rows(nc_master,gs_list) |> distinct()

future_map(unique(bills_to_process$UUID),
           ~scrape_bill(.x),
           .progress = TRUE,
           .options = furrr_options(seed = TRUE))   
