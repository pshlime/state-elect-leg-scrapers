##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Scrape NC from Open States
## Date: January 2025
## Author: Joe Loffredo
##################################################

library(tidyverse)
library(jsonlite)

DROPBOX_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/previous_leg_files/NC'

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



