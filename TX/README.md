# CA Election Bill Scrapers

## How to use Bill Scraper

To scrape a bill, call the method scrape_bill.

```
scrape_bill(UUID, session = NA, bill_number NA)
```

Expected input for scrape_bill

- UUID: (str) (e.g. "CA1995A2020")
- session: (str) (e.g. "1999-2000) -- this is an optional field, but use it if we have it
- bill_number: (str) (e.g. "AB 2020") -- this is an optional field, but use it if we have it

## Output files

Each category (bill_history, bill_metadata, sponsors, votes) have their own directory, as listed below. The file name is formatted by {uuid}.json, besides votes where each voting has its own file with the date attached to uuid.

Bill metadata, sponsorship, and history files are collected from the legacy CA Legislative Information site (http://leginfo.ca.gov). All voting information comes from data collected by Jeff Lewis (https://github.com/JeffreyBLewis/california-rollcall-votes),

Output Directories

```
\output\bill_history
\output\bill_metadata
\output\sponsors
\output\votes
```
