library(tidyverse)
library(glue)

vrleg_master_file <- readRDS("~/Desktop/GitHub/election-roll-call/bills/vrleg_master_file.rds")

gs_list <- googlesheets4::read_sheet('1f_vgVKQ2u95OYY9s0Nr8Wvfh6Pj8n8E3kh5FNl2XBz8') |> janitor::clean_names()
gs_list <- gs_list |> 
  mutate(
    session = as.character(session),
    bill_type = str_extract(bill_number, "^[A-Z]+"),
    bill_number = str_replace_all(bill_number, c("^HB"="","^SB"="","^HJR"="", "SJR"="")),
    bill_number_uuid = str_remove(bill_number, "^0+"),
    bill_type_uuid = case_match(
      bill_type,
      "HB" ~ "H",
      "SB" ~ "S",
      .default = bill_type
    ),
    year = str_extract(session, "^[0-9]{4}"),
    UUID = glue("UT{year}{bill_type_uuid}{bill_number_uuid}"),
    bill_number = glue("{bill_type}{bill_number}")
  ) |>
  select(UUID, session, bill_number)

ut_master <- vrleg_master_file |> 
  filter(STATE == 'UT' & YEAR %in% c(1995:2014)) |>
  mutate(
    bill_id = str_remove_all(UUID, "UT"),
    session = str_extract(bill_id, "^[0-9]{4}"),
    bill_type = str_extract(bill_id, "[A-Z]+"),
    bill_type = case_match(
      bill_type,
      "H" ~ "HB",
      "S" ~ "SB",
      .default = bill_type
    ),
    bill_number = str_extract(bill_id, "[0-9]+$"),
    bill_number = case_when(
      bill_type %in% c("HB","SB") ~ str_pad(bill_number, 4, pad = "0"),
      TRUE ~ str_pad(bill_number, 3, pad = "0")
    ),
    bill_number = glue("{bill_type}{bill_number}")
  ) |>
  select(UUID, session, bill_number)

bills_to_process <- bind_rows(ut_master,gs_list) |> distinct()

write_csv(bills_to_process, "UT/output/UT_bills_to_process.csv")
