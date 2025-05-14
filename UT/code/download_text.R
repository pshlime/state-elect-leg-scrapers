##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Scrape UT Bill Text
## Date: May 2025
## Author: Joe Loffredo
##################################################

rm(list = ls())
gc()

library(tidyverse)
library(jsonlite)
library(rvest)
library(glue)
library(furrr)
library(fs)

plan(multisession, workers = 11)

# Functions
clean_html <- function(html_content) {
  html_content <- str_replace_all(html_content, "<p[^>]*>", " ")
  html_content <- str_replace_all(html_content, "</p>", " ")
  html_content <- str_replace_all(html_content, "<div[^>]*>", " ")
  html_content <- str_replace_all(html_content, "</div>", " ")
  html_content <- str_replace_all(html_content, "<a[^>]*>", " ")
  html_content <- str_replace_all(html_content, "</a>", " ")
  html_content <- str_replace_all(html_content, '<u>', '<u class="amendmentInsertedText">')
  html_content <- str_replace_all(html_content, '<s>', '<strike class="amendmentDeletedText">')
  html_content <- str_replace_all(html_content, '</s>', '</strike>')
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
  html_content <- str_replace_all(html_content, "\\s+", " ")
  html_content <- str_replace_all(html_content, "<center[^>]*>", " ")
  html_content <- str_replace_all(html_content, "</center[^>]*>", " ")
  html_content <- str_replace_all(html_content, "<table[^>]*>", " ")
  html_content <- str_replace_all(html_content, "</table[^>]*>", " ")
  html_content <- str_replace_all(html_content, "\\[", " ")
  html_content <- str_replace_all(html_content, "\\]", " ")
  html_content <- str_replace_all(html_content, "</u> <u>", " ")
  html_content <- str_replace_all(html_content, "</u><u>", " ")
  html_content <- str_replace_all(html_content, ' </pre>', ' ')
  html_content <- str_replace_all(html_content, '<font[^>]*>', '')
  html_content <- str_replace_all(html_content, '</font>', '')
  html_content <- str_replace_all(html_content, "<main[^>]*>", " ")
  html_content <- str_replace_all(html_content, "</main>", " ")
  html_content <- str_replace_all(html_content, "<!-- WP [^>]*?-->", "")
  html_content <- str_replace_all(html_content, "<!--.*?-->", "")
  html_content <- str_replace_all(html_content, '<!-- field: -->', '')
  html_content <- str_replace_all(html_content, '<!-- field: -->', '')
  html_content <- str_replace_all(html_content, '</body>', '')
  html_content <- str_replace_all(html_content, '<strong>', '')
  html_content <- str_replace_all(html_content, '</strong>', '')
  html_content <- str_replace_all(html_content, '<code>', '')
  html_content <- str_replace_all(html_content, '</code>', '')
  html_content <- str_replace_all(html_content, '<colgroup[^>]*>', '')
  html_content <- str_replace_all(html_content, '</colgroup>', '')
  html_content <- str_replace_all(html_content, '</u> [0-9]{1,3} <u class="amendmentInsertedText">', '')
  html_content <- str_replace_all(html_content, '</u> <u class="amendmentInsertedText">', ' ')
  
  html_content <- str_trim(html_content)
  return(html_content)
}

bills <- list.files(path = "UT/output/bill_metadata/", pattern = "*.json", full.names = TRUE) |>
  map_df(~ {
    json <- fromJSON(.x)
    # Remove NULL elements or replace with NA
    json[map_lgl(json, is.null)] <- NA
    as_tibble(json)
  })


scrape_text <- function(UUID, session, url){
  TEXT_OUTPUT_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/utah'
  
  dir_create(glue("{TEXT_OUTPUT_PATH}/{UUID}"))
  
  page <- read_html(url)
  if(session %in% c(1997:2001)){
    text_links <- page |> html_nodes("p a") |> html_attr("href") |> str_subset("^.*/bills/.*\\.htm$")
    text_links <- glue("https://le.utah.gov{text_links}")
    
    lapply(text_links, function(link) {
      page <- read_html(link)
      text <- page |> html_nodes("#main-content") |> as.character() |> clean_html() |> str_trim() |> str_squish()
      
      file_name <- (link |> str_split("/"))[[1]] |> tail(2) |> str_c(collapse = "_") |> str_remove(".htm")
      dest_file_path <- glue("{TEXT_OUTPUT_PATH}/{UUID}/{file_name}.txt")
      
      writeLines(text, dest_file_path)
    })} else{
      text_links <- page |> html_nodes("#billTextDiv a") |> html_attr("href") |> str_subset("^.*/bills/.*\\.htm$")
      text_links <- glue("https://le.utah.gov{text_links}")
      
      lapply(text_links, function(link) {
        page <- read_html(link)
        text <- page |> html_nodes("#main-content") |> as.character() |> clean_html() |> str_trim() |> str_squish()
        
        file_name <- (link |> str_split("/"))[[1]] |> tail(2) |> str_c(collapse = "_") |> str_remove(".htm")
        dest_file_path <- glue("{TEXT_OUTPUT_PATH}/{UUID}/{file_name}.txt")
        
        writeLines(text, dest_file_path)
    })
    
    }
}

bills |> 
  select(UUID = uuid, session, url = state_url) |>
  future_pmap(scrape_text)
