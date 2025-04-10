# WI Election Bill Scrapers

## How to use Bill Scraper

To scrape a bill, call the method scrape_bill.

```
scrape_bill(uuid, state, state_bill_id, session)
```

Expected input for scrape_bill

- uuid: (str) (e.g. "WI1995A694")
- state: (str) state abbreviation (in this case "WI")
- state_bill_id: (str) bill id including chamber (e.g. "AB694")
- session: (str) full session yes (e.g. "1995")

## Output files

Each category (bill_history, bill_metadata, sponsors, votes) have their own directory, as listed below. The file name is formatted by {uuid}.json, besides votes where each voting has its own file with the date attached to uuid.

Output Directories

```
\output\bill_history
\output\bill_metadata
\output\sponsors
\output\votes
```

There is also a file `code/bills.csv` which contains all of the Bill Text with columns uuid, session, bill_number, and link

## Additional notes
Votes are scraped from the journal using GPT. If roll call was unanimous, then "yea" value is set to "unanimous". Remember that when working the vote data later to transform this to the number of members in the chamber -- it won't necessarily be accurate because we won't have a record of who was present, but it'll suffice. When creating an individual-level roll call vote table, retrieve these unanimous votes and assign "yea" to all.
