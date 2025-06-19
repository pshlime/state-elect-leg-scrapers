##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Retrieve NV Bill IDs
## Date: June 2025
## Author: Joe Loffredo
##################################################

library(tidyverse)
library(glue)
library(rvest)

rm(list = ls())

doc_types <- c(1:9)
sessions <- c('71st2001', '72nd2003', '73rd2005', '74th2007',
              '75th2009', '76th2011', '77th2013')
session_lookup <- data.frame()
for(s in sessions){
  message(s)
  for(i in doc_types){
    message(i)
    
    url <- glue("https://www.leg.state.nv.us/Session/{s}/Reports/HistListBills.cfm?DoctypeID={i}")
    
    html <- read_html(url)
    
    element <- case_match(
      s,
      '77th2013' ~ "#ScrollMe a",
      '76th2011' ~ "#ScrollMe a",
      "75th2009" ~ "#ScrollMe a",
      "74th2007" ~ "table+ table a",
      "73rd2005" ~ "table+ table a",
      "72nd2003" ~ "table+ table a",
      "71st2001" ~ "p+ table a"
    )
    
    bill_links <- html |> html_elements(element) |> html_attr('href')
    bill_names <- html |> html_elements(element) |> html_text()
    
    if(!is_empty(bill_links)){
      bill_links <- glue("https://www.leg.state.nv.us/Session/{s}/Reports/{bill_links}")
      
      session_lookup <- rbind(
        session_lookup,
        data.frame(session_id = s, bill_id = bill_names, link = bill_links))
    }
  }
}

write_csv(session_lookup, 'text/state-scrapers/nv_bill_ids.csv')
