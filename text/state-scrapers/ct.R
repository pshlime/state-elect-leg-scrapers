##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Download CT Text
## Date: May 2025
## Author: Joe Loffredo
##################################################

rm(list = ls())
gc()

library(tidyverse)
library(rvest)
library(glue)
library(furrr)
library(fs)

plan(multisession, workers = 11)

clean_html <- function(html_content) {
  # First, handle the specific bracket pattern with exact matching
  html_content <- str_replace_all(
    html_content,
    "<b>\\[<span class=\"remove\"></span></b>(.*?)</font><b><font face=\"Book Antiqua\" size=\"\\+1\">\\]</font></b>",
    '<strike class="amendmentDeletedText">\\1</strike>'
  )
  
  # Handle inserted text
  html_content <- str_replace_all(html_content, '<u class=\"insert\">', '<u class="amendmentInsertedText">')
  html_content <- str_replace_all(html_content, '<u><u class=\"insert\">', '<u class="amendmentInsertedText">')
  
  # Remove or replace various HTML tags
  html_content <- str_replace_all(html_content, '<u>', ' ')
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
  html_content <- str_replace_all(html_content, "<center[^>]*>", " ")
  html_content <- str_replace_all(html_content, "</center[^>]*>", " ")
  html_content <- str_replace_all(html_content, "<table[^>]*>", " ")
  html_content <- str_replace_all(html_content, "</table[^>]*>", " ")
  html_content <- str_replace_all(html_content, "</u> <u>", " ")
  html_content <- str_replace_all(html_content, "</u><u>", " ")
  html_content <- str_replace_all(html_content, ' </pre>', ' ')
  html_content <- str_replace_all(html_content, '<font[^>]*>', '')
  html_content <- str_replace_all(html_content, '</font>', '')
  html_content <- str_replace_all(html_content, '<!-- field: [A-Za-z]+ -->', '')
  html_content <- str_replace_all(html_content, '<!-- field: -->', '')
  html_content <- str_replace_all(html_content, '</body>', '')
  html_content <- str_replace_all(html_content, '<strong>', '')
  html_content <- str_replace_all(html_content, '</strong>', '')
  html_content <- str_replace_all(html_content, '<code>', '')
  html_content <- str_replace_all(html_content, '</code>', '')
  html_content <- str_replace_all(html_content, '<colgroup[^>]*>', '')
  html_content <- str_replace_all(html_content, '</colgroup>', '')
  html_content <- str_replace_all(html_content, '</u> [0-9]{1,2} <u class="amendmentInsertedText">', '')
  html_content <- str_replace_all(html_content, '</u></u>', '</u>')
  
  # Normalize whitespace
  html_content <- str_replace_all(html_content, "\\s+", " ")
  
  # Remove embedded CSS rules
  html_content <- str_remove_all(html_content, "\\.[^{]+\\{[^}]+\\}")
  
  # Remove style tags
  html_content <- str_replace_all(html_content, "<style>", "")
  html_content <- str_replace_all(html_content, "</style>", "")
  
  # Clean up the final text
  html_content <- str_trim(html_content)
  
  return(html_content)
}

build_url <- function(session, bill_number){
  glue("https://www.cga.ct.gov/asp/cgabillstatus/cgabillstatus.asp?selBillType=Bill&which_year={session}&bill_num={bill_number}")
}

scrape_text <- function(UUID, session, bill_number){
  message(UUID)
  TEXT_OUTPUT_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/connecticut'
  
  url <- build_url(session, bill_number)
  response <- httr::GET(url, config = httr::config(ssl_verifypeer = FALSE))
  page_text <- httr::content(response, "text")
  
  page <- read_html(page_text)
  
  text_links <- page |>
    html_elements("a") |> 
    html_attr("href") |>
    str_subset("tob|TOB")
  
  text_links <- str_subset(text_links, ".htm")
  
  text_links <- glue("https://www.cga.ct.gov{text_links}")
  
  lapply(text_links, function(link) {
    tryCatch({
      dir_create(glue("{TEXT_OUTPUT_PATH}/{UUID}"))
      
      text <- httr::GET(link, config = httr::config(ssl_verifypeer = FALSE))
      text <- httr::content(text, "text")
      text <- read_html(text) |> html_nodes("p") |> as.character() |> paste(collapse = "\n") |> clean_html() |> str_squish() |> str_trim()
      
      # Create a filename based on the UUID and link
      filename <- basename(link) |> str_remove(".htm")
      # Write the text to a file
      write_lines(text, path = glue("{TEXT_OUTPUT_PATH}/{UUID}/{filename}.txt"))
      
    }, error = function(e) {
      message(glue("Error scraping {link}: {e$message}"))
    })
  })
}

vrleg_master_file <- readRDS("~/Desktop/GitHub/election-roll-call/bills/vrleg_master_file.rds")
master <- vrleg_master_file |> 
  filter(STATE == 'CT' & YEAR %in% c(1995:2014)) |>
  mutate(
    bill_id = str_remove_all(UUID, "CT"),
    session = str_extract(bill_id, "^[0-9]{4}"),
    bill_number = str_extract(bill_id, "[0-9]+$"),
  ) |>
  select(UUID, session, bill_number)

master |>
  future_pmap(scrape_text)

