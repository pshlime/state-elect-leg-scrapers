##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Build CA vote lookups
## Date: February 2025
## Author: Joe Loffredo
##################################################

library(tidyverse)
library(data.table)
library(glue)

rm(list = ls())
gc()

# Uses data and code from Jeff Lewis: https://github.com/JeffreyBLewis/california-rollcall-votes/blob/master/README.md

DROPBOX_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/previous_leg_files/CA'
votes_files <- list.files(DROPBOX_PATH, pattern = 'votes', full.names = TRUE, recursive = TRUE)
desc_files <- list.files(DROPBOX_PATH, pattern = 'desc', full.names = TRUE, recursive = TRUE)

get_session_votes <- function(session){
  scan(
    str_subset(votes_files, session),
    what = "character",
    sep = "\n",
    fileEncoding = "latin1"
  ) |>
    map_df(function(r)
      tibble(name = str_trim(str_sub(r, 1, 20)),
             vote = as.numeric(str_split(
               str_sub(r, 21,-1),
               pattern = ""
             )[[1]])) |>
        mutate(rcnum = 1:n())) |>
    filter(vote != 0) |> 
    mutate(session = session)
}

get_vote_desc <- function(session){
  read_tsv(
    str_subset(desc_files, session),
    col_names = c(
      "rcnum",
      "bill",
      "author",
      "topic",
      "date",
      "location",
      "motion",
      "yeas",
      "noes",
      "outcome"
    ),
    locale = readr::locale(encoding = 'latin1')
  ) |> mutate(session = session)
}

# Load data
sessions <- c('95-96', '97-98', '99-00', '01-02', '03-04', '05-06', '07-08')
votes <- sessions |> map_dfr(get_session_votes)
desc <- sessions |> map_dfr(get_vote_desc)

# Clean up votes data
votes <- votes |>
  mutate(
    vote = case_match(
      vote,
      1 ~ 'Yea', 
      6 ~ 'Nay', 
      9 ~ 'NV', 
      0 ~ 'Absent'
    ),
    session = case_match(
      session,
      '95-96' ~ '1995-1996',
      '97-98' ~ '1997-1998',
      '99-00' ~ '1999-2000',
      '01-02' ~ '2001-2002',
      '03-04' ~ '2003-2004',
      '05-06' ~ '2005-2006',
      '07-08' ~ '2007-2008'
    )
  ) |>
  rename(response = vote)

desc <- desc |>
  rename(vote_date = date) |>
  mutate(
    session = case_match(
      session,
      '95-96' ~ '1995-1996',
      '97-98' ~ '1997-1998',
      '99-00' ~ '1999-2000',
      '01-02' ~ '2001-2002',
      '03-04' ~ '2003-2004',
      '05-06' ~ '2005-2006',
      '07-08' ~ '2007-2008'
    ),
    state = 'CA',
    chamber = case_when(
      str_detect(location, "ASM.") ~ 'A',
      str_detect(location, "SEN.") ~ 'S'
    ),
    date = mdy(vote_date),
    motion = ifelse(str_detect(location, "FLOOR"), glue("Floor - {motion}"), glue("Committee - {location} - {motion}"))) |>
  rename(state_bill_id = bill, nays = noes, description = motion)

other_votes <- votes |>
  summarise(other = sum(response %in% c('Absent', 'NV'), na.rm = T), .by = c("rcnum", "session"))

ca_roll_call <- desc |> 
  left_join(other_votes, by = c("rcnum", "session")) |>
  left_join(votes, by = c("rcnum", "session")) |>
  select(state, session, state_bill_id, chamber, date, description, yeas, nays, other, name, response) |>
  group_by(state, session, state_bill_id, chamber, date, description, yeas, nays, other) |>
  nest(roll_call = c(name, response)) |>
  ungroup() |>
  filter(!is.na(chamber))

saveRDS(ca_roll_call, file = glue("{DROPBOX_PATH}/ca_roll_call.rds"))
