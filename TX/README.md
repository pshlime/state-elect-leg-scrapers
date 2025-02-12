# TX Election Bill Scrapers

Because of how challenging it is to collect roll call (or "record votes") votes in the Texas legislature, only use `scrape_text` (to collect bill text from the state's FTP site) and `scrape_bill` (to get bill metadata, sponsorship info, and bill history).

## How to use Bill Scraper

To scrape a bill, call the method scrape_bill.

```
scrape_bill(UUID, session = NA, bill_number NA)
```

Expected input for scrape_bill

- UUID: (str) (e.g. "TX1995H2020")
- session: (str) (e.g. "75R) -- this is an optional field, but use it if we have it
- bill_number: (str) (e.g. "HB 2020") -- this is an optional field, but use it if we have it

## Output files

Each category (bill_history, bill_metadata, sponsors) have their own directory, as listed below. The file name is formatted by {uuid}.json, besides votes where each voting has its own file with the date attached to uuid.

Bill metadata and sponsors collected from the legislative information site (`https://capitol.texas.gov`) while the bill text is collected from the legislature's FTP (`ftp://ftp.legis.state.tx.us`)

Output Directories

```
\output\bill_history
\output\bill_metadata
\output\sponsors
```
