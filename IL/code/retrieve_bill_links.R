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
  
  html_content <- str_trim(html_content)
  return(html_content)
}

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

retrieve_bill_text_link <- function(session, url){
  if(session %in% c('91', '92')){
    text_link <- url |> read_html() |>  html_nodes("a") |> html_attr("href") |> str_subset("groups") |> unique()
    return(glue("https://ilga.gov{text_link}"))
  } else{
    text_link <- url |> read_html() |> html_nodes(".legislinks") |> html_attr("href") |> str_subset("fulltext")
    text_link <- glue("https://ilga.gov{text_link}")
    raw_text_link <- text_link |> read_html() |> html_nodes("#toplinks a") |> html_attr("href") |> str_subset("legislation/fulltext")
    return(glue("https://ilga.gov{raw_text_link}"))
  }
}

get_text <- function(UUID, session, url){
  TEXT_OUTPUT_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/illinois'
  dir_create(glue("{TEXT_OUTPUT_PATH}/{UUID}"))
  dest_file_path <- glue("{TEXT_OUTPUT_PATH}/{UUID}/{UUID}.txt")
  
  if(session %in% c('91', '92')){
    text <- read_html(url) |> html_element('pre') |> as.character() |> clean_html() |> str_trim() |> str_squish()
  } else{
    text <- read_html(url) |> html_nodes('.notranslate .xsl') |> as.character() |> paste(collapse = "\n") |> clean_html() |> str_trim() |> str_squish()
  }
  
  writeLines(text, dest_file_path)
  
  return(dest_file_path)
  
}

save_bill_text <- function(UUID, session, bill_number){
  message(UUID)
  url <- build_url(session, bill_number)
  if(is_empty(url)){
    message(glue("No URL found for {UUID}"))
    return(NULL)
  } else{
    text_link <- retrieve_bill_text_link(session, url)
    bill_text <- get_text(UUID, session, text_link)
  }
  return(bill_text)
}

already_processed <- dir_ls('/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/illinois') |> basename()
bills_to_process <- read_csv("IL/output/il_bills_to_process.csv") |> distinct() |> filter(!(UUID %in% already_processed))

bills_to_process |> mutate(
  session = as.character(session),
  text_path = future_pmap(list(UUID, session, bill_number), save_bill_text))
