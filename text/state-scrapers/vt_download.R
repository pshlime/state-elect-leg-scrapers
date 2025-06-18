##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Download VT Text
## Date: June 2025
## Author: Joe Loffredo
##################################################

rm(list = ls())
gc()

library(tidyverse)
library(rvest)
library(glue)
library(fs)
library(furrr)

plan(multisession, workers = 6)

vt_text_links <- read_csv("text/state-scrapers/vt_bill_links.csv")

clean_html <- function(html_content) {
  # Handle markdown-style strikethrough first (~~text~~)
  html_content <- str_replace_all(html_content, '~~([^~]+)~~', '<strike class="amendmentDeletedText">\\1</strike>')
  
  # Handle class-based underlines ({.underline} format)
  html_content <- str_replace_all(html_content, '\\{\\.underline\\}', '')
  
  # Handle regular underlined text - convert to amendment markup
  html_content <- str_replace_all(html_content, '<u>', '<u class="amendmentInsertedText">')
  html_content <- str_replace_all(html_content, '<u([^>]*)>', '<u class="amendmentInsertedText">')
  
  # Handle strikethrough/deleted text
  html_content <- str_replace_all(html_content, '<s>', '<strike class="amendmentDeletedText">')
  html_content <- str_replace_all(html_content, '</s>', '</strike>')
  html_content <- str_replace_all(html_content, '<del>', '<strike class="amendmentDeletedText">')
  html_content <- str_replace_all(html_content, '</del>', '</strike>')
  
  # Handle text in square brackets as potential deletions (but be more selective)
  # Only handle brackets with capital letters or common legislative text patterns
  html_content <- str_replace_all(
    html_content,
    "\\[([A-Z][A-Z\\s\\.,;:]+?)\\]",
    '<strike class="amendmentDeletedText">\\1</strike>'
  )
  
  # Handle bracketed text that appears to be insertions (mixed case, longer text)
  # We'll wrap these in underlines for now - you may need to adjust based on your specific needs
  html_content <- str_replace_all(
    html_content,
    "\\[\\[([^\\]]+?)\\]\\]",
    '<u class="amendmentInsertedText">\\1</u>'
  )
  
  # Remove DOCTYPE and HTML structure tags
  html_content <- str_replace_all(html_content, '<!DOCTYPE[^>]*>', '')
  html_content <- str_replace_all(html_content, '<html[^>]*>', '')
  html_content <- str_replace_all(html_content, '</html>', '')
  html_content <- str_replace_all(html_content, '<head[^>]*>', '')
  html_content <- str_replace_all(html_content, '</head>', '')
  html_content <- str_replace_all(html_content, '<body[^>]*>', '')
  html_content <- str_replace_all(html_content, '</body>', '')
  
  # Remove style blocks completely (including content)
  html_content <- str_replace_all(html_content, '<style[^>]*>.*?</style>', '')
  
  # Remove meta tags
  html_content <- str_replace_all(html_content, '<meta[^>]*>', '')
  html_content <- str_replace_all(html_content, '<title[^>]*>.*?</title>', '')
  
  # Remove paragraph and div tags but preserve line breaks
  html_content <- str_replace_all(html_content, '<p[^>]*>', '\n')
  html_content <- str_replace_all(html_content, '</p>', '\n')
  html_content <- str_replace_all(html_content, '<div[^>]*>', '\n')
  html_content <- str_replace_all(html_content, '</div>', '\n')
  
  # Remove header tags but preserve structure
  html_content <- str_replace_all(html_content, '<h[1-6][^>]*>', '\n')
  html_content <- str_replace_all(html_content, '</h[1-6]>', '\n')
  
  # Remove span tags (often used for styling) and their style attributes
  html_content <- str_replace_all(html_content, '<span[^>]*>', '')
  html_content <- str_replace_all(html_content, '</span>', '')
  
  # Remove inline style attributes from any remaining tags
  html_content <- str_replace_all(html_content, '\\s*style="[^"]*"', '')
  html_content <- str_replace_all(html_content, "\\s*style='[^']*'", '')
  
  # Remove font formatting tags
  html_content <- str_replace_all(html_content, '<font[^>]*>', '')
  html_content <- str_replace_all(html_content, '</font>', '')
  html_content <- str_replace_all(html_content, '<b[^>]*>', '')
  html_content <- str_replace_all(html_content, '</b>', '')
  html_content <- str_replace_all(html_content, '<i[^>]*>', '')
  html_content <- str_replace_all(html_content, '</i>', '')
  html_content <- str_replace_all(html_content, '<strong[^>]*>', '')
  html_content <- str_replace_all(html_content, '</strong>', '')
  html_content <- str_replace_all(html_content, '<em[^>]*>', '')
  html_content <- str_replace_all(html_content, '</em>', '')
  
  # Remove table-related tags
  html_content <- str_replace_all(html_content, '<table[^>]*>', '')
  html_content <- str_replace_all(html_content, '</table>', '')
  html_content <- str_replace_all(html_content, '<tr[^>]*>', '')
  html_content <- str_replace_all(html_content, '</tr>', '')
  html_content <- str_replace_all(html_content, '<td[^>]*>', '')
  html_content <- str_replace_all(html_content, '</td>', '')
  html_content <- str_replace_all(html_content, '<th[^>]*>', '')
  html_content <- str_replace_all(html_content, '</th>', '')
  html_content <- str_replace_all(html_content, '<colgroup[^>]*>', '')
  html_content <- str_replace_all(html_content, '</colgroup>', '')
  
  # Remove other common tags
  html_content <- str_replace_all(html_content, '<a[^>]*>', '')
  html_content <- str_replace_all(html_content, '</a>', '')
  html_content <- str_replace_all(html_content, '<center[^>]*>', '')
  html_content <- str_replace_all(html_content, '</center>', '')
  html_content <- str_replace_all(html_content, '<code[^>]*>', '')
  html_content <- str_replace_all(html_content, '</code>', '')
  html_content <- str_replace_all(html_content, '<pre[^>]*>', '')
  html_content <- str_replace_all(html_content, '</pre>', '')
  
  # Remove line breaks that are HTML encoded
  html_content <- str_replace_all(html_content, '<br[^>]*>', '\n')
  
  # Remove any remaining HTML comments
  html_content <- str_replace_all(html_content, '<!--.*?-->', '')
  
  # Remove CSS-style rules that might be embedded
  html_content <- str_remove_all(html_content, "\\.[^{]+\\{[^}]+\\}")
  
  # Clean up amendment markup - remove duplicate or adjacent tags
  html_content <- str_replace_all(html_content, '</u>\\s*<u class="amendmentInsertedText">', ' ')
  html_content <- str_replace_all(html_content, '</u><u class="amendmentInsertedText">', '')
  html_content <- str_replace_all(html_content, '</strike>\\s*<strike class="amendmentDeletedText">', ' ')
  html_content <- str_replace_all(html_content, '</strike><strike class="amendmentDeletedText">', '')
  
  # Remove field comments specific to legislative documents
  html_content <- str_replace_all(html_content, '<!-- field: [A-Za-z]+ -->', '')
  html_content <- str_replace_all(html_content, '<!-- field: -->', '')
  
  # Remove section markers and other document-specific formatting
  html_content <- str_replace_all(html_content, '^:::', '')
  html_content <- str_replace_all(html_content, ':::$', '')
  html_content <- str_replace_all(html_content, '\\n:::', '\n')
  
  # Clean up whitespace
  html_content <- str_replace_all(html_content, '\\s+', ' ')
  html_content <- str_replace_all(html_content, '\\n\\s+', '\n')
  html_content <- str_replace_all(html_content, '\\s+\\n', '\n')
  html_content <- str_replace_all(html_content, '\\n+', '\n')
  
  # Final trim
  html_content <- str_trim(html_content)
  
  return(html_content)
}

build_url <- function(session, bill_number) {
  if(session %in% c('2010','2012','2014')){
    glue("https://legislature.vermont.gov/bill/status/2010/{bill_number}")
  } else{
    vt_text_links |> filter(session_year == session & bill_id == bill_number) |> pull(full_url)
  }
}

scrape_text <- function(UUID, session, bill_number){
  message(UUID)
  
  TEXT_OUTPUT_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/vermont'
  
  url <- build_url(session, bill_number)
  if(!is_empty(url)){
    response <- httr::GET(url, config = httr::config(ssl_verifypeer = FALSE, followlocation = TRUE))
  } else{
    message(glue("No URL found for {UUID}"))
    return(NULL)
  }
  
  if(response$status_code != 200){
    message(url)
    message(glue("Failed to fetch {UUID} - status code: {response$status_code}"))
    return(NULL)
  } else{
    dir_create(glue("{TEXT_OUTPUT_PATH}/{UUID}"))
    
    if(session %in% c('2010','2012','2014')){
      page_text <- httr::content(response, "text")
      page <- read_html(page_text)
      
      text_links <- page |> 
        html_nodes("a") |>
        html_attr("href") |>
        str_subset("bills|BILLS") |>
        str_subset("pdf")
      
      text_links <- glue("https://legislature.vermont.gov{text_links}")
      
      if(!is_empty(text_links)){
        lapply(text_links, function(link) {
          file_name <- basename(link)
          file_path <- glue("{TEXT_OUTPUT_PATH}/{UUID}/{file_name}")
          
          download.file(link, file_path)
        })
      }
    } else{
      text <- read_html(url) |>
        html_nodes("body") |>
        as.character() |>
        clean_html() |>
        str_trim() |>
        str_squish()
      
      filename <- basename(url) |> str_remove(".HTM")
      # Write the text to a file
      write_lines(text, path = glue("{TEXT_OUTPUT_PATH}/{UUID}/{filename}_html.txt"))
    }
  }
  
  Sys.sleep(5)
}

vrleg_master_file <- readRDS("~/Desktop/GitHub/election-roll-call/bills/vrleg_master_file.rds")
master <- vrleg_master_file |> 
  filter(STATE == 'VT'  & (YEAR %in% c(1995:2010) | YEAR %in% c(2011:2014) & is.na(ls_bill_id))) |>
  mutate(
    bill_id = str_remove_all(UUID, "VT"),
    year = str_extract(bill_id, "^[0-9]{4}"),
    session = case_when(
      year %in% c('2013', '2014') ~ '2014',
      year %in% c('2011', '2012') ~ '2012',
      year %in% c('2009', '2010') ~ '2010',
      year %in% c('2007', '2008') ~ '2008',
      year %in% c('2005', '2006') ~ '2006',
      year %in% c('2003', '2004') ~ '2004',
      year %in% c('2001', '2002') ~ '2002',
      TRUE ~ NA_character_
    ),
    bill_type = str_extract(bill_id, "[A-Z]+"),
    bill_type = case_match(
      bill_type,
      "H" ~ "H.",
      "S" ~ "S.",
      'SR' ~ "S.R.",
      'HR' ~ "H.R.",
      'HJR' ~ "J.R.H.",
      'SJR' ~ "J.R.S.",
      'HCR' ~ "H.C.R.",
      'SCR' ~ "S.C.R.",
      .default = bill_type
    ),
    bill_number = str_extract(bill_id, "[0-9]+$"),
    bill_number = ifelse(session %in% c('2002','2004','2006','2008'), str_pad(bill_number, width = 4, side = "left", pad = "0"), bill_number),
    bill_number = glue("{bill_type}{bill_number}")
  ) |>
  select(UUID, session, bill_number) |>
  distinct()

master |>
  filter(!(UUID %in% list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/vermont"))) |>
  future_pmap(scrape_text, .progress = T)

get_rank <- function(file_name) {
  case_when(
    str_detect(file_name, "Enacted.pdf") ~ 4,
    str_detect(file_name, "Passed%20by%20Both%20House%20and%20Senate.pdf") ~ 3,
    str_detect(file_name, "Passed%20by%20the%20Senate.pdf") ~ 2,
    str_detect(file_name, "Passed%20by%20the%20House.pdf") ~ 2,
    TRUE ~ 1
  )
}

bill_text_files <- data.frame(
  file_path = list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/vermont", pattern = "*.pdf", full.names = TRUE, recursive = TRUE)) |>
  mutate(
    file_name = basename(file_path),
    rank = get_rank(file_name),
    UUID = str_remove(file_path, file_name) |> basename()) |>
  group_by(UUID) |>
  slice_max(order_by = rank, n = 1) |>
  ungroup() |>
  select(UUID, file_path) |>
  write_csv("text/state-scrapers/vt_bill_text_files.csv")

