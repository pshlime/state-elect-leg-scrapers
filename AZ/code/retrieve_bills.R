library(tidyverse)
library(glue)

vrleg_master_file <- readRDS("~/Desktop/GitHub/election-roll-call/bills/vrleg_master_file.rds")

gs_list <- googlesheets4::read_sheet('1iLK5BroppEcy8d0OCyHQ_chs5Yy96h4mZU69TIqGRis') |> janitor::clean_names()
gs_list <- gs_list |> 
  mutate(
    session = as.character(session),
    bill_type = str_extract(bill_number, "^[A-Z]+"),
    bill_number = str_replace_all(bill_number, c("^HB"="","^SB"="","^HJR"="", "SJR"="","HCR"="", "SCR"="")),
    bill_type_uuid = case_match(
      bill_type,
      "HB" ~ "H",
      "SB" ~ "S",
      .default = bill_type
    ),
    year = str_extract(session, "^[0-9]{4}"),
    UUID = glue("AZ{year}{bill_type_uuid}{bill_number}"),
    bill_number = glue("{bill_type}{bill_number}")
  ) |>
  select(UUID, session, bill_number)

az_master <- vrleg_master_file |> 
  filter(STATE == 'AZ' & YEAR %in% c(1995:2014)) |>
  mutate(
    bill_id = str_remove_all(UUID, 'AZ'),
    session = str_extract(bill_id, "^[0-9]{4}"),
    session = case_match(
      session,
      "1995" ~ "1995 - Forty-second Legislature - First Regular Session",
      "1996" ~ "1996 - Forty-second Legislature - Second Regular Session",
      "1997" ~ "1997 - Forty-third Legislature - First Regular Session",
      "1998" ~ "1998 - Forty-third Legislature - Second Regular Session",
      "1999" ~ "1999 - Forty-fourth Legislature - First Regular Session",
      "2000" ~ "2000 - Forty-fourth Legislature - Second Regular Session",
      "2001" ~ "2001 - Forty-fifth Legislature - First Regular Session",
      "2002" ~ "2002 - Forty-fifth Legislature - Second Regular Session",
      "2003" ~ "2003 - Forty-sixth Legislature - First Regular Session",
      "2004" ~ "2004 - Forty-sixth Legislature - Second Regular Session",
      "2005" ~ "2005 - Forty-seventh Legislature - First Regular Session",
      "2006" ~ "2006 - Forty-seventh Legislature - Second Regular Session",
      "2007" ~ "2007 - Forty-eighth Legislature - First Regular Session",
      "2008" ~ "2008 - Forty-eighth Legislature - Second Regular Session",
      "2009" ~ "2009 - Forty-ninth Legislature - First Regular Session",
      "2010" ~ "2010 - Forty-ninth Legislature - Second Regular Session",
      "2011" ~ "2011 - Fiftieth Legislature - First Regular Session",
      "2012" ~ "2012 - Fiftieth Legislature - Second Regular Session",
      "2013" ~ "2013 - Fifty-first Legislature - First Regular Session",
      "2014" ~ "2014 - Fifty-first Legislature - Second Regular Session"
    ), 
    bill_type = str_extract(bill_id, "[A-Z]+"),
    bill_type = case_match(
      bill_type,
      "H" ~ "HB",
      "S" ~ "SB",
      .default = bill_type
    ),
    bill_number = str_extract(bill_id, "[0-9]+$"),
    bill_number = glue("{bill_type}{bill_number}")
  ) |>
  select(UUID, session, bill_number)

bills_to_process <- bind_rows(az_master,gs_list) |> distinct()

write_csv(bills_to_process, "AZ/output/AZ_bills_to_process.csv")
