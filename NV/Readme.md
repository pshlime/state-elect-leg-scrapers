# Nevada Legislative Data Pipeline

A multi-stage Python toolkit to scrape, parse, and combine Nevada legislative data (bills, summaries, statuses, sponsors, history, votes) into unified JSON outputs.

---

## 🚀 Overview

This repo automates the end-to-end conversion of raw NV legislative webpages into four final JSON datasets:

1. **bill_metadata.json**  
2. **sponsors.json**  
3. **bill_history.json**  
4. **votes.json**

It is organized into discrete steps:
1. **Index → Base Data**  
2. **Base Data → Metadata**  
3. **Sponsor Search & Sponsor Parsing**  
4. **History Parsing**  
5. **Votes Parsing**  
6. **Combine All Outputs**

Each step lives in `conversion_functions/<step_name>.py` and can be run independently or all at once via the top-level launcher.

---

## ⚙️ Prerequisites

- Python 3.8+  
- Install dependencies with a virtual environment:
  python -m venv .venv
  source .venv/bin/activate
  pip install -r requirements.txt





.
├── code/
│   └── start.py                # Step 1: Runs all the scripts end-to-end
│   ├── index_to_json.py        # Step 2: Scrape bill index → JSON
│   ├── basedata.py             # Step 3: Normalize base JSON
│   ├── metadata.py             # Step 4: Summaries, statuses, AN ACT titles
│   ├── sponsorsearch.py        # Step 5a: Scrape primary/cosponsor lists  
│   ├── sponsors.py             # Step 6b: Adds Sponsors and Cosponsors to their respective bills
│   ├── history.py              # Step 7: Parse bill history actions
│   ├── votes.py                # Step 8: Parse roll-call votes
│   └── combiner.py             # Step 9: Stitch everything into 4 big JSONs
│
│
├── intermediate/               # ← Default working area
│   ├── index_to_json/          # raw JSONs outputs from the bill index sites
│   ├── basedata/               # normalized base data that every bill inherits and reads
│   ├── metadata/               # bill_metadata_*.json
│   ├── sponsors/               # sponsor_search + sponsors outputs
│   ├── history/                # parsed history JSONs
│   └── votes/                  # parsed vote JSONs
│
├── output/                     # ← Final combined JSONs
│   ├── bill_metadata.json
│   ├── sponsors.json
│   ├── bill_history.json
│   └── votes.json
│
├── requirements.txt
└── README.md

