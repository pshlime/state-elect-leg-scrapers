import requests
import urllib.parse
import json
import time
import csv

BASE_URL = "https://www.oregonlegislature.gov"
LIST_ID = "{CA51C8F5-A8FA-4078-B75E-DB5863A1D5C5}"
VIEW_ID = "{C822C01C-F591-47CF-B1AF-44B149BEFBF4}"
LIST_VIEW_URL = f"{BASE_URL}/bills_laws/Pages/archived-bills.aspx"

HEADERS = {
    "Accept": "*/*",
    "Content-Type": "application/x-www-form-urlencoded",
    "Origin": BASE_URL,
    "Referer": LIST_VIEW_URL,
    "User-Agent": "Mozilla/5.0"
}

SESSIONS = [
    "2005 Regular Session",
    "2003 Regular Session",
    "2001 Regular Session"
]

def fetch_session(session_name, delay=0.8):
    print(f"\n📘 Fetching: {session_name}")
    all_rows = []
    page_row = 1
    seen_ids = set()
    paging_info = {}

    while True:
        group_string = urllib.parse.quote(f";#{session_name};#")
        paged_params = {
            "List": LIST_ID,
            "View": VIEW_ID,
            "ViewCount": "19",
            "IsXslView": "TRUE",
            "IsCSR": "TRUE",
            "ListViewPageUrl": urllib.parse.quote_plus(LIST_VIEW_URL),
            "GroupString": group_string,
            "IsGroupRender": "TRUE",
            "WebPartID": VIEW_ID
        }

        # Add paging tokens if we have them
        if paging_info:
            paged_params.update({
                "Paged": "TRUE",
                "PageFirstRow": str(page_row),
                "p_ID": paging_info["p_ID"],
                "p_Title": urllib.parse.quote(paging_info["p_Title"]),
                "p_Session": urllib.parse.quote(session_name),
                "p_SortBehavior": "0",
                "FolderCTID": "0x012001"
            })

        query_string = "&".join(f"{k}={v}" for k, v in paged_params.items())
        url = f"{BASE_URL}/bills_laws/_layouts/15/inplview.aspx?{query_string}"

        resp = requests.post(url, headers=HEADERS)
        if not resp.ok:
            print(f"❌ Failed to fetch page at row {page_row} of {session_name}")
            break

        json_start = resp.text.find('{')
        try:
            data = json.loads(resp.text[json_start:])
        except Exception as e:
            print("⚠️ Failed to parse JSON:", e)
            break

        rows = data.get("Row", [])
        if not rows:
            print(f"🚫 No more rows at page starting with {page_row}")
            break

        current_ids = set(row.get("ID") for row in rows)
        if current_ids.issubset(seen_ids):
            print(f"⚠️ Detected duplicate page at row {page_row}, stopping pagination.")
            break
        seen_ids.update(current_ids)

        for row in rows:
            file_path = row.get("FileRef")
            title = row.get("Title", "Untitled")
            if file_path:
                full_url = f"{BASE_URL}{file_path}"
                all_rows.append((session_name, title, full_url))

        # Save pagination info from last row
        last_row = rows[-1]
        paging_info = {
            "p_ID": last_row["ID"],
            "p_Title": last_row["Title"]
        }

        print(f"✅ Page {page_row}-{page_row + len(rows) - 1}: {len(rows)} items")
        page_row += len(rows)
        time.sleep(delay)

    return all_rows

# Run for all sessions
results = []
for session in SESSIONS:
    results.extend(fetch_session(session))

# Save or print
for session, title, url in results:
    print(f"{session}\t{title}\t{url}")

with open("text/state-scrapers/or_archived_bill_links.csv", "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["session_name", "title", "full_url"])
    writer.writerows(results)

print("✅ Saved to oregon_archived_bills.csv")
