##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Download IN Text
## Date: June 2025
## Author: Joe Loffredo
##################################################

rm(list = ls())
gc()

library(tidyverse)
library(rvest)
library(glue)
library(fs)
library(polite)
library(httr)
library(furrr)

plan(multisession, workers = 11)

clean_html <- function(html_content) {
  html_content <- str_replace_all(html_content, '<b>', '<u class="amendmentInsertedText">')
  html_content <- str_replace_all(html_content, '</b>', '</u>')
  html_content <- str_replace_all(html_content, '<strike>', '<strike class="amendmentDeletedText">')
  html_content <- str_remove_all(html_content, "<!--\\[if[^\\]]*\\]>[\\s\\S]*?<!\\[endif\\]-->")
  # Remove Office/Word VML and Smart Tags (v:, o:, w:, etc.)
  html_content <- str_remove_all(html_content, "<v:[^>]+>[\\s\\S]*?</v:[^>]+>")
  html_content <- str_remove_all(html_content, "<o:[^>]+>[\\s\\S]*?</o:[^>]+>")
  html_content <- str_remove_all(html_content, "<w:[^>]+>[\\s\\S]*?</w:[^>]+>")
  html_content <- str_remove_all(html_content, "<v:[^>]+\\s*/>")
  html_content <- str_remove_all(html_content, "<o:[^>]+\\s*/>")
  html_content <- str_remove_all(html_content, "<w:[^>]+\\s*/>")
  # Remove smart tag wrappers but keep inner text
  html_content <- str_remove_all(html_content, "<(state|place|placename|placetype|city|county|country)[^>]*>")
  html_content <- str_remove_all(html_content, "</(state|place|placename|placetype|city|county|country)>")
  
  html_content <- str_remove_all(html_content, "<wrapblock[\\s\\S]*?</wrapblock>")
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
  html_content <- str_replace_all(html_content, "\\s+", " ")
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
  html_content <- str_replace_all(html_content, '<!-- Font [A-Za-z0-9\\s]+ -->', '')
  html_content <- str_replace_all(html_content, '<!-- End of font [A-Za-z0-9\\s]+ -->', '')
  html_content <- str_replace_all(html_content, '<!-- field: -->', '')
  html_content <- str_replace_all(html_content, "<!-- WP Comment[^>]*--&gt;", "")
  html_content <- str_replace_all(html_content, '</body>', '')
  html_content <- str_replace_all(html_content, '<strong>', '')
  html_content <- str_replace_all(html_content, '</strong>', '')
  html_content <- str_replace_all(html_content, '<code>', '')
  html_content <- str_replace_all(html_content, '</code>', '')
  html_content <- str_replace_all(html_content, '<colgroup[^>]*>', '')
  html_content <- str_replace_all(html_content, '</colgroup>', '')
  html_content <- str_replace_all(html_content, '</u> <u class="amendmentInsertedText">', '')
  # Remove embedded CSS rules like `.highlight { ... }` or `.Page1::before { ... }`
  html_content <- str_remove_all(html_content, "\\.[^{]+\\{[^}]+\\}")
  
  # Remove remaining style tags (already in your function, kept for completeness)
  html_content <- str_replace_all(html_content, "<style>", "")
  html_content <- str_replace_all(html_content, "</style>", "")
  
  html_content <- str_trim(html_content)
  html_content <- str_replace_all(html_content, '<hr width=\"[0-9]+\" size=\"[0-9]+\" align=\"Center\">', " ")
  html_content <- str_replace_all(
    html_content,
    "<hr> <!-- File converted by Wp2Html Version 3.1 --> <!-- Email Andy.Scriven@research.natpower.co.uk for more details --> <!-- WP Style Open: System_34 -->    <!-- WP Style End: System_34 -->", 
    "")
  return(html_content)
}

parse_text <- function(response){
  text <- response |> html_element("body") |> as.character() |>
    str_remove_all("<!--.*?-->") |>
    str_remove_all("<body[^>]*>") |>
    str_remove_all("</body>") |>
    str_remove_all("<(?!/?(?:b|strike)(?:\\s|>))[^>]*>") |>
    str_replace_all("\\s+", " ") |>
    str_replace_all("\\n\\s*", "\n") |>
    str_replace_all("\\n{3,}", "\n\n") |>
    str_trim()
  
  text <- str_remove_all(text, 'PRINTING CODE. Amendments: Whenever an existing statute (or a section of the Indiana Constitution) is being amended, the text of the existing provision will appear in this style type, additions will appear in <b> this style type</b>, and deletions will appear in <strike>this</strike> <strike>style</strike> <strike>type.</strike> Additions: Whenever a new statutory provision is being enacted (or a new constitutional provision adopted), the text of the new provision will appear in <b> this style type</b>. Also, the word <b> NEW</b> will appear in that style type in the introductory clause of each SECTION that adds a new provision to the Indiana Code or the Indiana Constitution. Conflict reconciliation: Text in a statute in this style type or <strike>this</strike> <strike>style</strike> <strike>type</strike> reconciles conflicts between statutes enacted by the [0-9]{4} Regular and Special Sessions of the General Assembly.')
  text <- str_replace_all(text, "<b>", "<u class=\"amendmentInsertedText\">")
  text <- str_replace_all(text, "</b>", "</u>")
  text <- str_replace_all(text, "<strike>", "<strike class=\"amendmentDeletedText\">")
  
  return(text)
}

retrieve_html <- function(url){
  my_bow <- bow(
    url,
    force = TRUE,
    user_agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36",
    config = httr::config(
      ssl_verifypeer = FALSE, 
      followlocation = FALSE
    )
  )
  
  polite::scrape(my_bow)
}

scrape_text <- function(UUID, session, bill_type, bill_number) {
  message(UUID)
  TEXT_OUTPUT_PATH <- '/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/indiana'
  
  dir_create(glue("{TEXT_OUTPUT_PATH}/{UUID}"))
  
  # Define bill stages based on bill type
  if(bill_type %in% c('SB', 'SJ', 'SR')) {
    bill_stages <- c('IN', 'SB', 'ES', 'SE')
  } else if (bill_type %in% c('HB', 'HJ', 'HR')) {
    bill_stages <- c('IN', 'HB', 'EH', 'HE')
  } else {
    stop("Unsupported bill type: ", bill_type)
  }
  
  # Iterate over each bill stage
  for (stage in bill_stages) {
    last_valid_response <- NULL
    version_number <- 1
    
    # Construct the initial URL with version number
    url <- glue("https://archive.iga.in.gov/{session}/bills/{stage}/{stage}{bill_number}.{version_number}.html")
    message("Trying URL: ", url)
    
    # Loop through version numbers for each stage until a version doesn't exist
    while (TRUE) {
      response <- tryCatch({
        retrieve_html(url)
      }, error = function(e) {
        message("An error occurred: ", e$message)
        return(NULL)
      })
      
      if (!is.null(response)) {
        last_valid_response <- response  # Update with the valid response
        version_number <- version_number + 1  # Increment version number to try the next version
        url <- glue("https://archive.iga.in.gov/{session}/bills/{stage}/{stage}{bill_number}.{version_number}.html")
        message("Trying next version: ", url)
      } else {
        break  # Break when a version doesn't exist
      }
    }
    
    # If a valid response was found, parse and save the content
    if (!is.null(last_valid_response)) {
      parsed_text <- parse_text(last_valid_response)
      file_name <- glue("{TEXT_OUTPUT_PATH}/{UUID}/{bill_type}{bill_number}_{stage}_{version_number - 1}.txt")
      write_lines(parsed_text, file_name)
    } else {
      message("No valid response found for stage: ", stage)
    }
  }
}


vrleg_master_file <- readRDS("~/Desktop/GitHub/election-roll-call/bills/vrleg_master_file.rds")
master <- vrleg_master_file |> 
  filter(STATE == 'IN' & YEAR %in% c(1995:2014)) |>
  mutate(
    bill_id = str_remove_all(UUID, "IN"),
    year = str_extract(bill_id, "^[0-9]{4}"),
    bill_type = str_extract(bill_id, "[A-Z]+"),
    bill_type = case_match(
      bill_type,
      "H" ~ "HB",
      "S" ~ "SB",
      "SJRR" ~ "SJ",
      "HJR" ~ "HJ",
      .default = bill_type
    ),
    bill_number = str_extract(bill_id, "[0-9]+$"),
    bill_number = str_pad(bill_number, width = 4, side = "left", pad = "0")
  ) |>
  select(UUID, session = year, bill_type, bill_number)

master |>
  filter(!(UUID %in% list.files(path = "/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/indiana"))) |>
  future_pmap(scrape_text)
