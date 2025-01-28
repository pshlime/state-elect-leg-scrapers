# NC Election Bill Scrapers

## How to use Bill Scraper

To scrape a bill, call the method scrape_bill.

```
scrape_bill(uuid)
```

Expected input for scrape_bill

- uuid: (str) (e.g. "AZ1995H2020")

## Output files

Each category (bill_history, bill_metadata, sponsors, votes) have their own directory, as listed below. The file name is formatted by {uuid}.json, besides votes where each voting has its own file with the date attached to uuid.

All data was originally collected by Open States. bill_history, bill_metadata, and sponsors data begins in 1995; vote data begins in 2001.

Output Directories

```
\output\bill_history
\output\bill_metadata
\output\sponsors
\output\votes
```
