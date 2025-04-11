##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Scrape WA
## Date: April 2025
## Author: Joe Loffredo
##################################################

library(tidyverse)
library(jsonlite)
library(glue)
library(httr)
library(xml2)

rm(list = ls())
gc()

OUTPUT_PATH <- 'WA/output'

# Functions
build_url <- function(session, bill_number){
  glue("https://app.leg.wa.gov/billsummary?BillNumber={bill_number}&Year={session}#rollCallPopup")
}


get_bill_metadata <- function(UUID, session, bill_number){
  # Build legislative info site url
  state_url <- build_url(session, bill_number)
  
  # Extract metadata from GetLegislation
  payload <- list(biennium = session, billNumber = bill_number)
  
  response <- POST(url = "https://wslwebservices.leg.wa.gov/LegislationService.asmx/GetLegislation", body = payload, encode = "form")
  
  if (status_code(response) == 200) {
    # Parse the response content
    metadata <- content(response, as = "parsed")
    legislation_nodes <- xml_find_all(metadata, "//d1:ArrayOfLegislation/d1:Legislation", ns = xml_ns(metadata))
    metadata <- as_list(legislation_nodes)
    ## Get latest version
    metadata <- metadata[[length(metadata)]]
    ## Get values
    title <- metadata$LegalTitle |> unlist()
    description <- metadata$LongDescription |> unlist()
    status <- metadata$CurrentStatus$HistoryLine |> unlist()
    status <- ifelse(str_detect(status,"Effective|Chapter"), glue("Enacted - {status}"), status)
    
    tibble(
      uuid = UUID, 
      state = 'WA', 
      session = session, 
      state_bill_id = bill_number, 
      title = title,
      description = description,
      status = status,
      state_url = state_url
    ) |> as.list() |> toJSON(auto_unbox = T, pretty = T) |> writeLines(glue("{OUTPUT_PATH}/bill_metadata/{UUID}.json"))
  } else {
    message("error getting bill metadata")
    return(NULL)
  }
  
}

get_sponsors <- function(UUID, session, bill_number){
  # Extract metadata from GetLegislation
  payload <- list(biennium = session, billId = bill_number)
  
  response <- POST(url = "https://wslwebservices.leg.wa.gov/LegislationService.asmx/GetSponsors", body = payload, encode = "form")
  
  if (status_code(response) == 200) {
    sponsors <- content(response, as = "parsed")
    sponsors_nodes <- xml_find_all(sponsors, "//d1:ArrayOfSponsor/d1:Sponsor", ns = xml_ns(sponsors))
    sponsors <- as_list(sponsors_nodes)
    
    flatten_sponsor <- function(sponsor) {
      list(
        Id = sponsor$Id[[1]],
        Name = sponsor$Name[[1]],
        LongName = sponsor$LongName[[1]],
        Agency = sponsor$Agency[[1]],
        Acronym = sponsor$Acronym[[1]],
        Type = sponsor$Type[[1]],
        Order = sponsor$Order[[1]],
        Phone = sponsor$Phone[[1]],
        Email = sponsor$Email[[1]],
        FirstName = sponsor$FirstName[[1]],
        LastName = sponsor$LastName[[1]]
      )
    }
    
    sponsors_df <- map_dfr(sponsors, flatten_sponsor) |> mutate(Type = ifelse(Type == 'Primary', 'sponsor', 'cosponsor'))
    
    tibble(
      uuid = UUID, 
      state = 'WA', 
      session = session, 
      state_bill_id = bill_number, 
      sponsor_name = sponsors_df$Name,
      sponsor_type = sponsors_df$Type
    ) |> 
      group_by(uuid, state, session, state_bill_id) |>
      nest(sponsors = c(sponsor_name, sponsor_type)) |>
      ungroup() |>
      as.list() |>
      toJSON(pretty = T,auto_unbox = T) |> 
      writeLines(glue("{OUTPUT_PATH}/sponsors/{UUID}.json"))
    } else {
    message("error getting sponsors")
    return(NULL)
  }
  
}

scrape_bill <- function(UUID, session = NA, bill_number = NA){
  metadata <- get_bill_metadata()
  sponsors <- get_sponsors()
}

session = '2021-22'
UUID = 'WA2021SB5015'
bill_number = 5015
