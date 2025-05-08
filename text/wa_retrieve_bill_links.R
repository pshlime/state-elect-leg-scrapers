##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Retrieve WA Text
## Date: May 2025
## Author: Joe Loffredo
##################################################

rm(list = ls())
gc()

library(tidyverse)
library(rvest)
library(glue)
library(fs)
library(furrr)

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
  html_content <- str_replace_all(html_content, '<font size="[0-9]+">', '')
  html_content <- str_replace_all(html_content, '</font>', '')
  html_content <- str_replace_all(html_content, '<!-- field: [A-Za-z]+ -->', '')
  html_content <- str_replace_all(html_content, '<!-- field: -->', '')
  html_content <- str_replace_all(html_content, '</body>', '')
  html_content <- str_trim(html_content)
  return(html_content)
}

build_url <- function(session, bill_number){
  glue("https://app.leg.wa.gov/bi/tld/documentsearchresults?biennium={session}&name={bill_number}&documentType=1")
}

retrieve_links <- function(url){
  page <- read_html(url)
  page |> 
    html_elements('#DocumentsReportTable a:nth-child(2)') |> 
    html_attr("href") |> 
    str_subset("Bills")
}

retrieve_text <- function(UUID, session, bill_number) {
  message(UUID)
  
  TEXT_OUTPUT_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/washington'
  url <- build_url(session, bill_number)
  links <- retrieve_links(url)
  
  if (length(links) == 0) {
    return(NULL)
  } else {
    dir_create(glue("{TEXT_OUTPUT_PATH}/{UUID}"))
    
    dest_file_paths <- lapply(links, function(link) {
      file_name <- basename(link) |> str_remove_all(".htm$")
      dest_file_path <- glue("{TEXT_OUTPUT_PATH}/{UUID}/{file_name}.txt")
      
      tryCatch({
        text <- read_html(link) |> html_element('body') |> as.character() |> clean_html() |> str_trim() |> str_squish()
        text <- str_replace_all(text, "_", "")
        
        message("Writing HTML format text file: ", dest_file_path)
        writeLines(text, dest_file_path)
      }, error = function(e) {
        message(glue("Error downloading {link}: {e$message}"))
      })
      
      return(dest_file_path)
    })
    
    return(dest_file_paths)
  }
}


# Build list of UUIDs
vrleg_master_file <- readRDS("~/Desktop/GitHub/election-roll-call/bills/vrleg_master_file.rds")
gs_wa_list <- googlesheets4::read_sheet('1jzW_WzyAAEFKxTGZeSmyIn9UQpXhHqsEb5zCBmni228') |> janitor::clean_names()

gs_wa_list <- gs_wa_list |> 
  mutate(
    bill_type = str_extract(bill_number, "^[A-Z]+"),
    bill_number = str_extract(bill_number, "[0-9]+$"),
    bill_type = case_match(
      bill_type,
      "SB" ~ "S",
      "HB" ~ "H",
      .default = bill_type
    ),
    session = case_match(
      session,
      "1995-1996" ~ '1995-96',
      "1997-1998" ~ '1997-98',
      "1999-2000" ~ '1999-00'
    ),
    UUID = glue("WA{year}{bill_type}{bill_number}")
  ) |>
  select(UUID, session, bill_number)

wa_master <- vrleg_master_file |> 
  filter(STATE == 'WA' & YEAR %in% c(1995:2014)) |>
  mutate(
    bill_id = str_remove_all(UUID, "WA"),
    session = str_extract(bill_id, "^[0-9]{4}"),
    bill_type = str_extract(bill_id, "[A-Z]+"),
    bill_number = str_extract(bill_id, "[0-9]+$"),
    session = case_when(
      session %in% c('2001','2002') ~ '2001-02',
      session %in% c('2003','2004') ~ '2003-04',
      session %in% c('2005','2006') ~ '2005-06',
      session %in% c('2007','2008') ~ '2007-08',
      session %in% c('2009','2010') ~ '2009-10',
      session %in% c('2011','2012') ~ '2011-12',
      session %in% c('2013','2014') ~ '2013-14'
    )
  ) |>
  select(UUID, session, bill_number)


already_processed <- dir_ls('/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/washington') |> basename()
bills_to_process <- bind_rows(gs_wa_list, wa_master) |> distinct() |> filter(!(UUID %in% already_processed))

bills_to_process <- bills_to_process |> mutate(pdf_path = future_pmap(list(UUID, session, bill_number), retrieve_text))
bills_to_process <- bills_to_process |> unnest_longer(pdf_path)

write_csv(bills_to_process, 'text/wa_bill_text_files.csv')
