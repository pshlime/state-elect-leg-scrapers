
library(tidyverse)
library(glue)

vrleg_master_file <- readRDS("~/Desktop/GitHub/election-roll-call/bills/vrleg_master_file.rds")

ga_leg_list <- read_csv("GA/output/ga_legislation_by_session.csv") |>
  filter(grepl("election|vote|voti|elector|ballot", Caption, ignore.case = TRUE) & grepl("ballot|absentee|mail|primary|primaries|registration|polling|place|audit|identification|redistricting|worker|recount|campaign|poll|audit|board of election|certify|HAVA", Caption, ignore.case = TRUE))

ga_master <- vrleg_master_file |> 
  filter(STATE == 'GA' & YEAR %in% c(1995:2014)) |>
  mutate(
    bill_id = str_remove_all(UUID, "GA"),
    session = str_extract(bill_id, "^[0-9]{4}"),
    bill_type = str_extract(bill_id, "[A-Z]+"),
    bill_type = case_match(
      bill_type,
      "H" ~ "HB",
      "S" ~ "SB",
      .default = bill_type
    ),
    bill_number = str_extract(bill_id, "[0-9]+$"),
    session = case_when(
      session %in% c('2001','2002') ~ '2001_02',
      session %in% c('2003','2004') ~ '2003_04',
      session %in% c('2005','2006') ~ '2005_06',
      session %in% c('2007','2008') ~ '2007_08',
      session %in% c('2009','2010') ~ '2009_10',
      session %in% c('2011','2012') ~ '2011_12',
      session %in% c('2013','2014') ~ '2013_14'
    ),
    bill_number = glue("{bill_type} {bill_number}")
  ) |>
  select(UUID, session, bill_number)

output <- ga_master |>
  right_join(ga_leg_list, by = c("session" = 'Session', "bill_number"='Description')) |>
  mutate(
    year = str_extract(session, "^[0-9]{4}"),
    bill_number_uuid = str_remove_all(bill_number,"\\s") |>
      str_replace_all(c("HB" = "H", "SB" = "S")),
    UUID = ifelse(is.na(UUID), glue("GA{year}{bill_number_uuid}"),UUID)
  ) |>
  select(UUID, ga_id = Id, session, bill_number, caption = Caption)

write_csv(output, "GA/output/ga_legislation_by_session_merged.csv")
