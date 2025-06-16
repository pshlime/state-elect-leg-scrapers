##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Retrieve MO Senate Links
## Date: June 2025
## Author: Joe Loffredo
##################################################

library(tidyverse)
library(rvest)
library(glue)

retrieve_links <- function(session){
  url <- glue("https://senate.mo.gov/{session}info/BTS_Web/BillList.aspx?SessionType=R")
  
  page <- read_html(url)
  
  bill_numbers <- page |>
    html_nodes("a[id*='hlBillNum']") |>
    html_text() |>
    str_remove_all("\\s")
  
  # Extract URLs
  bill_urls <- page |>
    html_nodes("a[id*='hlBillNum']") |>
    html_attr("href")
  
  bill_urls <- glue("https://senate.mo.gov/{session}info/BTS_Web/{bill_urls}")
  
  # Combine into a data frame
  data.frame(
    session_id = session,
    bill_id = bill_numbers,
    url = bill_urls,
    stringsAsFactors = FALSE
  )
}

sessions <- c("04", "05", "06", "07", "08", "09", "10", "11", "12", "13", "14")

# Retrieve links for each session
all_links <- map_df(sessions, retrieve_links)

# Save the links to a CSV file
write_csv(all_links, "text/state-scrapers/mo_senate_links.csv")
