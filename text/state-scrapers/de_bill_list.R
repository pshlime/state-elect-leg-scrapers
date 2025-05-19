##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Build DE Bill ID Xwalk
## Date: May 2025
## Author: Joe Loffredo (modified)
##################################################

rm(list = ls())
gc()

library(jsonlite)
library(httr)
library(dplyr)
library(furrr)
library(future)

# Set up parallel processing with 11 workers
plan(multisession, workers = 11)

# Function to fetch legislation data with pagination
fetch_legislation_page <- function(ga_number, page = 1, page_size = 20) {
  # The API endpoint for legislation data
  url <- "https://legis.delaware.gov/json/AllLegislation/GetAllLegislation"
  
  # Create the parameters for a single GA
  body_params <- list(
    sort = "",
    page = page,
    pageSize = page_size,
    group = "",
    filter = "",
    "selectedGA[0]" = ga_number,
    sponsorName = "",
    fromIntroDate = "",
    toIntroDate = "",
    coSponsorCheck = "false"
  )
  
  # Make the POST request with appropriate headers
  response <- tryCatch({
    POST(
      url = url,
      body = body_params,
      encode = "form",
      add_headers(
        "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        "Accept" = "application/json, text/plain, */*",
        "Referer" = "https://legis.delaware.gov/",
        "Origin" = "https://legis.delaware.gov",
        "Content-Type" = "application/x-www-form-urlencoded"
      )
    )
  }, error = function(e) {
    message(sprintf("Error making request for GA %d page %d: %s", ga_number, page, e$message))
    return(NULL)
  })
  
  # Check if the request was successful
  if (is.null(response) || status_code(response) != 200) {
    message(sprintf("Failed to fetch GA %d page %d. Status code: %s", 
                    ga_number, page, ifelse(is.null(response), "NULL", status_code(response))))
    return(NULL)
  }
  
  # Parse the JSON response
  data <- tryCatch({
    content(response, "parsed")
  }, error = function(e) {
    message(sprintf("Error parsing JSON for GA %d page %d: %s", ga_number, page, e$message))
    return(NULL)
  })
  
  return(data)
}

# Function to fetch all legislation data for a single GA number
get_delaware_legislation <- function(ga_number, page_size = 100) {
  message(sprintf("Fetching legislation data for GA session: %d", ga_number))
  
  # Get the first page to determine total records
  first_page <- fetch_legislation_page(ga_number, 1, page_size)
  
  if (is.null(first_page) || !("Total" %in% names(first_page))) {
    message(sprintf("Failed to get total record count for GA %d", ga_number))
    return(NULL)
  }
  
  total_records <- first_page$Total
  total_pages <- ceiling(total_records / page_size)
  
  message(sprintf("Found %d total records across %d pages for GA %d", 
                  total_records, total_pages, ga_number))
  
  # Store all legislation data
  all_data <- first_page$Data
  
  # If there are more pages, fetch them
  if (total_pages > 1) {
    for (page_num in 2:total_pages) {
      # Small delay to avoid hammering the server
      Sys.sleep(0.2)
      
      page_data <- fetch_legislation_page(ga_number, page_num, page_size)
      
      if (!is.null(page_data) && "Data" %in% names(page_data) && length(page_data$Data) > 0) {
        all_data <- c(all_data, page_data$Data)
      } else {
        message(sprintf("Warning: No data returned for GA %d page %d", ga_number, page_num))
      }
    }
  }
  
  # Convert list of records to a data frame
  if (length(all_data) > 0) {
    result_df <- bind_rows(all_data)
    message(sprintf("Successfully fetched %d records for GA %d", nrow(result_df), ga_number))
    
    # Add GA number as a column for reference
    result_df$GA_Number <- ga_number
    
    # Clean date fields
    date_columns <- grep("DateTime$", names(result_df), value = TRUE)
    for (col in date_columns) {
      result_df[[col]] <- sapply(result_df[[col]], function(x) {
        if (is.na(x) || is.null(x)) return(NA)
        # Extract timestamp from .NET date format: /Date(timestamp)/
        timestamp <- as.numeric(gsub(".*\\((\\d+)\\).*", "\\1", x)) / 1000
        as.POSIXct(timestamp, origin = "1970-01-01", tz = "UTC")
      })
    }
    
    return(result_df)
  } else {
    message(sprintf("No records found for GA %d", ga_number))
    return(NULL)
  }
}

# Main execution
# Define GA sessions to fetch
ga_numbers <- 141:148
legislation_list <- future_map(ga_numbers, get_delaware_legislation)

# Filter out NULL results
legislation_list <- legislation_list[!sapply(legislation_list, is.null)]
legislation_data <- bind_rows(legislation_list)

saveRDS(legislation_data, file = "text/state-scrapers/de_legislation_data.rds")
