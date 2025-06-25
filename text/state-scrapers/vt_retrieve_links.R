##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Retrieve VT Text Links
## Date: June 2025
## Author: Joe Loffredo
##################################################

library(rvest)
library(dplyr)
library(stringr)
library(purrr)
library(tibble)

# Create URL combinations
urls <- expand_grid(body = c("H", "S"), session_year = c(2008, 2006, 2004, 2002)) |>
  mutate(url = str_glue("http://www.leg.state.vt.us/docs/bills.cfm?Body={body}&Session={session_year}"))

# Scrape single URL with simpler approach
scrape_bills_from_url <- function(url, body_type, session_year) {
  cat("Scraping:", url, "\n")
  Sys.sleep(1)
  
  tryCatch({
    html_content <- read_html(url)
    
    # Get all DT elements (bill headers)
    dt_elements <- html_content |> html_elements("dt")
    
    # Get all DD elements (links)
    dd_elements <- html_content |> html_elements("dd")
    
    cat("Found", length(dt_elements), "bills and", length(dd_elements), "links\n")
    
    if (length(dt_elements) == 0) {
      return(tibble(
        session_year = integer(),
        body = character(),
        bill_number = character(),
        link_text = character(),
        url = character()
      ))
    }
    
    # Extract bill numbers and titles from DT elements
    bill_info <- dt_elements |>
      map_dfr(~ {
        text <- html_text2(.x)
        bill_pattern <- str_glue("{body_type}\\.\\d+")
        bill_num <- str_extract(text, bill_pattern)
        tibble(bill_number = bill_num, bill_text = text)
      }) |>
      filter(!is.na(bill_number))
    
    cat("Extracted", nrow(bill_info), "valid bill numbers\n")
    
    if (nrow(bill_info) == 0) {
      return(tibble(
        session_year = integer(),
        body = character(),
        bill_number = character(),
        link_text = character(),
        url = character()
      ))
    }
    
    # Process DD elements and match to bills
    # This is tricky because we need to figure out which DD belongs to which DT
    all_elements <- html_content |> html_elements("dt, dd")
    
    results <- tibble()
    current_bill <- NA_character_
    
    for (element in all_elements) {
      if (html_name(element) == "dt") {
        # Extract bill number
        text <- html_text2(element)
        bill_pattern <- str_glue("{body_type}\\.\\d+")
        current_bill <- str_extract(text, bill_pattern)
      } else if (html_name(element) == "dd" && !is.na(current_bill)) {
        # Extract link info
        link_elem <- element |> html_element("a")
        
        if (!is.null(link_elem)) {
          link_text <- html_text2(link_elem)
          link_url <- html_attr(link_elem, "href")
        } else {
          link_text <- html_text2(element)
          link_url <- NA_character_
        }
        
        # Add to results
        results <- results |>
          bind_rows(tibble(
            session_year = session_year,
            body = body_type,
            bill_number = current_bill,
            link_text = str_trim(link_text),
            url = link_url
          ))
      }
    }
    
    cat("Final result:", nrow(results), "links\n\n")
    return(results)
    
  }, error = function(e) {
    cat("Error:", e$message, "\n\n")
    return(tibble(
      session_year = integer(),
      body = character(),
      bill_number = character(),
      link_text = character(),
      url = character()
    ))
  })
}

# Scrape all URLs
vermont_bills <- urls |>
  pmap_dfr(~ scrape_bills_from_url(..3, ..1, ..2)) |>
  mutate(
    full_url = if_else(
      !is.na(url),
      str_c("http://www.leg.state.vt.us", url),
      NA_character_
    )
  )

# Clean up
get_rank <- function(body, full_url) {
  case_when(
    str_detect(full_url, "acts") ~ 5,
    str_detect(full_url, "passed") ~ 4,
    body == 'S' & str_detect(full_url, "bills/house") ~ 3,
    body == 'H' & str_detect(full_url, "bills/senate") ~ 3,
    body == 'H' & str_detect(full_url, "bills/house") ~ 2,
    body == 'S' & str_detect(full_url, "bills/senate") ~ 2,
    TRUE ~ 1
  )
}

vermont_bills <- vermont_bills |>
  drop_na() |>
  filter(link_text != 'Act Summary') |>
  mutate(rank = get_rank(body, full_url)) |>
  select(-c(url)) |>
  group_by(session_year, bill_number) |>
  slice_max(order_by = rank, n = 1) |>
  ungroup() |> 
  select(-c(rank, body, link_text)) |>
  rename(bill_id = bill_number)
  

write_csv(vermont_bills, "text/state-scrapers/vt_bill_links.csv")