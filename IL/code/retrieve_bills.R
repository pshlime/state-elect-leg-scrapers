library(tidyverse)
library(glue)

vrleg_master_file <- readRDS("~/Desktop/GitHub/election-roll-call/bills/vrleg_master_file.rds")

gs_list <- googlesheets4::read_sheet('1X1ZYou4W8IrAAxT5T0tbYdUcrnZ5CEZCL50RGVmg2K8') |> janitor::clean_names()
gs_list <- gs_list |> 
  mutate(
    bill_number = str_replace(bill_number, "-",""),
    bill_type = str_extract(bill_number, "^[A-Z]+"),
    bill_number = str_extract(bill_number, "[0-9]+$"),
    bill_type_uuid = case_match(
      bill_type,
      "HB" ~ "H",
      "SB" ~ "S",
      .default = bill_type
    ),
    year = str_extract(session, "^[0-9]{4}"),
    session = str_remove(session, "^[0-9]{4}-"),
    UUID = glue("IL{year}{bill_type_uuid}{bill_number}"),
    bill_number = glue("{bill_type}{bill_number}")
  ) |>
  select(UUID, session, bill_number)

il_master <- vrleg_master_file |> 
  filter(STATE == 'IL' & YEAR %in% c(1995:2014)) |>
  mutate(
    bill_id = str_remove_all(UUID, "IL"),
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
      session %in% c('2001','2002') ~ '92',
      session %in% c('2003','2004') ~ '93',
      session %in% c('2005','2006') ~ '94',
      session %in% c('2007','2008') ~ '95',
      session %in% c('2009','2010') ~ '96',
      session %in% c('2011','2012') ~ '97',
      session %in% c('2013','2014') ~ '98'
    ),
    bill_number = glue("{bill_type}{bill_number}")
  ) |>
  select(UUID, session, bill_number)

bills_to_process <- bind_rows(il_master,gs_list) |> distinct()

write_csv(bills_to_process, "IL/output/il_bills_to_process.csv")