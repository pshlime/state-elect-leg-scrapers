##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Retrieve IL Text
## Date: May 2025
## Author: Joe Loffredo
##################################################

rm(list=ls())
gc()

library(tidyverse)
library(rvest)
library(glue)
library(fs)
library(furrr)

plan(multisession, workers = 11)

build_url <- function(session, bill_number){
  bill_type <- str_extract(bill_number, "^[A-Z]+")
  bill_number <- str_extract(bill_number, "\\d+")
  bill_number <- str_pad(bill_number, 4, pad = "0")
  
  if(session %in% c('91', '92')){
    url <- glue("https://ilga.gov/legislation/legisnet{session}/status/{session}0{bill_type}{bill_number}.html")
  } else{
    session_id <- case_match(
      session,
      '93' ~ '3',
      '94' ~ '50',
      '95' ~ '51',
      '96' ~ '76',
      '97' ~ '84',
      '98' ~ '85'
    )
    bill_range_start <- ((as.numeric(bill_number) - 1) %/% 100) * 100 + 1
    bill_range_end <- bill_range_start + 99
    
    lookup_url <- glue("https://ilga.gov/legislation/grplist.asp?num1={bill_range_start}&num2={bill_range_end}&DocTypeID={bill_type}&GA={session}&SessionId={session_id}")
    lookup_nodes <- read_html(lookup_url) |> html_nodes("li a")
    lookup_links_df <- tibble(
      text = lookup_nodes |> html_text(trim = TRUE),
      href = lookup_nodes |> html_attr("href")
    )
    
    url <- lookup_links_df |> filter(str_detect(text, glue("{bill_type}{bill_number}"))) |> pull(href)
    url <- glue("https://ilga.gov{url}")
  }
  
  return(url)
}
