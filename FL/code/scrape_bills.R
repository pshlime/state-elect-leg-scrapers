##################################################
## Project: State Election Legislation Scrapers
## Script purpose: Scrape FL
## Date: April 2025
## Author: Joe Loffredo
##################################################

library(tidyverse)
library(jsonlite)
library(glue)
library(httr)
library(xml2)
library(rvest)

rm(list = ls())
gc()

OUTPUT_PATH <- 'FL/output'
HEADERS <- c(
  "Accept" = "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
  "Accept-Encoding" = "gzip, deflate, br, zstd",
  "Accept-Language" = "en-US,en;q=0.9",
  "Cache-Control" = "max-age=0",
  "Connection" = "keep-alive",
  "Cookie" = "_gcl_au=1.1.922952014.1744867225; ASP.NET_SessionId=vi5vza44oewjaasgcanrjntg; _gid=GA1.2.1971583501.1745332184; _ga=GA1.2.1257031925.1744867225; _ga_9ZYRS0B7FN=GS1.1.1745332183.5.1.1745333068.0.0.0; TS011a9ece=010b53be0db986840215846becc751d59fef54157202ffef97f04e423a4ec2e4bf34b00007001d7138c7c78fb94f216d2f3489a7d0; session_cookie_mfhp=!9uq8wEqMQvE9fOMoo5GqtdkYuDcADk22z8SGfbzXYweT5Gs+R+sybSoSsFQ6xtrsAbN46XPRBDDbFw==; TS54fca245027=083632b602ab2000bb3dd03a6cf62d15a592744b66a3f77187f043ce67b8fdfb453bf1444e589d2808500ee6e21130009c4c48af7f2ba71cabe8add00e1eb483a70ee0b826858e2d0a816060084cd972c3fa259b4b6e4e29d4a64b95caeaf1a3",
  "Host" = "www.flhouse.gov",
  "Sec-Fetch-Dest" = "document",
  "Sec-Fetch-Mode" = "navigate",
  "Sec-Fetch-Site" = "none",
  "Sec-Fetch-User" = "?1",
  "Upgrade-Insecure-Requests" = "1",
  "User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36",
  "sec-ch-ua" = "\"Chromium\";v=\"134\", \"Not:A-Brand\";v=\"24\", \"Google Chrome\";v=\"134\"",
  "sec-ch-ua-mobile" = "?0",
  "sec-ch-ua-platform" = "\"macOS\""
)

# Functions
build_url <- function(session, bill_number){
  if(str_detect(bill_number, "SJR|SB") | str_detect(bill_number, "HB|HJR") & session %in% c("48", "49", "50", "51", "71", "72")){
    # Senate bills
    # Pull just number
    bill_number <- str_extract(bill_number, "\\d+")
    glue("https://www.flsenate.gov/Session/Bill/{session}/{bill_number}")
  } else {
    # House bills
    bill_number <- str_extract(bill_number, "\\d+")
    search_url <- glue("https://www.flhouse.gov/Sections/Bills/bills.aspx?chamber=B&sessionId={session}&billNumber={bill_number}")
    
    # Perform the GET request with custom headers
    search_response <- GET(search_url, add_headers(.headers = HEADERS))
    
    # Read the HTML content from the response
    search_html <- content(search_response, "text") |> read_html()
    
    # Extract bill id
    bill_url <- search_html |> html_nodes("#result-block > ul > li > a") |> html_attr("href")
    glue("https://www.flhouse.gov{bill_url}")
  }
}


get_bill_metadata <- function(UUID, session, bill_number, state_url, state_html){
  if(str_detect(state_url, "senate")){
    title <- state_html |> html_nodes("h2") |> html_text() |> str_squish() |> tail(1)
    description <- state_html |> html_nodes(".width80") |> html_text() |> str_squish()
    status <- state_html |> 
      html_nodes(".pad-left0") |> 
      html_text() |> 
      str_extract("Last Action:[^|]+") |> 
      str_trim() |>
      str_squish() |>
      str_replace_all("Last Action: [0-9]{1,2}/[0-9]{1,2}/[0-9]{2,4}", "") |>
      str_replace_all("Bill Text: Web Page", "") |>
      str_trim()
    
    status <- ifelse(str_detect(status, "Chapter"), glue("Enacted - {status}"), status)
    
  } else if(str_detect(state_url, "house")){
    title <- state_html |> html_nodes("#header-bill-subject") |> html_text() |> str_squish()
    description <- state_html |> html_nodes("#bill-subject") |> html_text() |> str_squish()
    status <- state_html |> html_nodes("#lblLastAction") |> html_text() |> str_squish()
    status <- ifelse(str_detect(status, "Chapter"), glue("Enacted - {status}"), status)
  }
    tibble(
      uuid = UUID, 
      state = 'FL', 
      session = session, 
      state_bill_id = bill_number, 
      title = title,
      description = description,
      status = status,
      state_url = state_url
    ) |> as.list() |> toJSON(auto_unbox = T, pretty = T) |> writeLines(glue("{OUTPUT_PATH}/bill_metadata/{UUID}.json"))
}

get_sponsors <- function(UUID, session, bill_number, state_url, state_html){
  if(str_detect(state_url, "senate")){
    sponsors_list <- state_html |> html_nodes("#main > div > div.grid-100 > p:nth-child(5)") |> html_text() |> str_trim() |> str_squish()
    sponsors_list <- str_split(sponsors_list, ";")[[1]]
    sponsors_list <- str_trim(sponsors_list)
    cosponsor_index <- which(str_detect(sponsors_list, "\\(CO-INTRODUCERS\\)"))
    
    if(!is_empty(cosponsor_index)){
      sponsors <- sponsors_list[1:(cosponsor_index - 1)] |>
        str_replace_all(c("GENERAL BILL by "="","LOCAL BILL by"="","JOINT RESOLUTION by"="")) |>
        str_trim()
      sponsors_df <- data.frame(sponsor_name = c(sponsors), sponsor_type = "sponsor")
      cosponsors <- sponsors_list[(cosponsor_index + 1):length(sponsors_list)] |>
        str_replace_all("\\(CO-INTRODUCERS\\)", "") |>
        str_trim()
      cosponsors_df <- data.frame(sponsor_name = c(cosponsors), sponsor_type = "cosponsor")
      
      sponsors_df <- bind_rows(sponsors_df, cosponsors_df)
    } else{
      sponsors <- sponsors_list |>
        str_replace_all(c("GENERAL BILL by "="","LOCAL BILL by"="","JOINT RESOLUTION by"="")) |>
        str_trim()
      sponsors_df <- data.frame(sponsor_name = c(sponsors), sponsor_type = "sponsor")
    }
  } else if(str_detect(state_url, "house")){
    sponsors <- state_html |> 
      html_nodes("#lblSponsors") |> 
      html_text() |> 
      str_squish()
    sponsors_df <- data.frame(sponsor_name = c(sponsors), sponsor_type = "sponsor")
  }
  
  tibble(
    uuid = UUID, 
    state = 'FL', 
    session = session, 
    state_bill_id = bill_number, 
    sponsor_name = sponsors_df$sponsor_name,
    sponsor_type = sponsors_df$sponsor_type
  ) |> 
    group_by(uuid, state, session, state_bill_id) |>
    nest(sponsors = c(sponsor_name, sponsor_type)) |>
    ungroup() |>
    as.list() |>
    toJSON(pretty = T,auto_unbox = T) |> 
    writeLines(glue("{OUTPUT_PATH}/sponsors/{UUID}.json"))
}

get_bill_history <- function(UUID, session, bill_number, state_url, state_html){
  if(str_detect(state_url, "senate")){
    history_df <- state_html |>
      html_node("#tabBodyBillHistory") |>
      html_table(fill = T) |>
      mutate(
        date = as_date(Date, format = "%m/%d/%Y"),
        Action = str_remove_all(Action, "• ") |> str_trim() |> str_squish(),
        action = glue("{Chamber} - {Action}"),
        action = str_replace_all(action, c("^Senate - "="S - ","House - "="H - "))
      ) |>
      select(date, action)
  } else if(str_detect(state_url, "house")){
    
  }
  
  tibble(
    uuid = UUID, 
    state = 'FL', 
    session = session, 
    state_bill_id = bill_number, 
    date = history_df$date,
    action = history_df$action
  ) |> 
    group_by(uuid, state, session, state_bill_id) |>
    nest(history = c(date, action)) |>
    ungroup() |>
    as.list() |>
    toJSON(pretty = T,auto_unbox = T) |> 
    writeLines(glue("{OUTPUT_PATH}/bill_history/{UUID}.json"))
}

get_votes <- function(UUID, session, bill_number){
    
    votes_df <- map_dfr(votes, flatten_votes) |>
      mutate(
        uuid = UUID,
        state = 'FL',
        session = session,
        state_bill_id = bill_number,
        chamber = case_match(
          Agency,
          'Senate' ~ 'S',
          'House' ~ 'H',
          .default = NA_character_
        ),
        date = as_date(VoteDate),
        description = Motion,
        yeas = as.integer(YeaVotes),
        nays = as.integer(NayVotes),
        other = as.integer(AbsentVotes) + as.integer(ExcusedVotes),
      ) |>
      select(uuid, state, session, state_bill_id, chamber, date, description, yeas, nays, other, roll_call)
    
    for(i in 1:nrow(votes_df)){
      votes_df |>
        slice(i) |>
        as.list() |>
        toJSON(pretty = T, auto_unbox = T) |>
        writeLines(glue("{OUTPUT_PATH}/votes/{UUID}_{i}.json"))
    }
}

scrape_bill <- function(UUID, session = NA, bill_number = NA){
  session <- as.character(session)
  session <- case_when(
    str_detect(bill_number, "HB|HJR") & session == '2002' ~ '4',
    str_detect(bill_number, "HB|HJR") & session == '2003' ~ '28',
    str_detect(bill_number, "HB|HJR") & session == '2004' ~ '36',
    str_detect(bill_number, "HB|HJR") & session == '2005' ~ '38',
    str_detect(bill_number, "HB|HJR") & session == '2006' ~ '42',
    str_detect(bill_number, "HB|HJR") & session == '2007' ~ '54',
    str_detect(bill_number, "HB|HJR") & session == '2008' ~ '57',
    str_detect(bill_number, "HB|HJR") & session == '2009' ~ '61',
    str_detect(bill_number, "HB|HJR") & session == '2010' ~ '64',
    str_detect(bill_number, "HB|HJR") & session == '2011' ~ '66'
  )
  
  state_url <- build_url(session, bill_number)
  if (str_detect(bill_number, "SB|SJR") | str_detect(bill_number, "HB|HJR") & session %in% c("1998","1999","2000","2001","2001A")) {
    state_html <- read_html(state_url)
  } else if (str_detect(bill_number, "HB|HJR")) {
    state_html <- GET(state_url, add_headers(.headers = HEADERS)) |> content("text") |> read_html()
  }
  
  get_bill_metadata(UUID, session, bill_number, state_url, state_html)
  get_sponsors(UUID, session, bill_number, state_url, state_html)
  get_bill_history(UUID, session, bill_number)
  get_votes(UUID, session, bill_number)
}

# ## Testing
# session = '2021-22'
# UUID = 'WA2021SB5015'
# bill_number = 5015
# scrape_bill(UUID, session, bill_number)


