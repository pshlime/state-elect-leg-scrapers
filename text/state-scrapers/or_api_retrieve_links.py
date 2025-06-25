import requests
import pandas as pd
from urllib.parse import quote
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed

BASE_URL = "https://api.oregonlegislature.gov/odata/ODataService.svc/"
LOG_EVERY = 50
MAX_WORKERS = 10

def get_sessions():
    url = f"{BASE_URL}LegislativeSessions?$format=json"
    response = requests.get(url)
    response.raise_for_status()
    return response.json()['value']

def get_measures(session_key):
    url = f"{BASE_URL}Measures?$filter=SessionKey eq '{session_key}'&$format=json"
    response = requests.get(url)
    response.raise_for_status()
    return response.json()['value']

def process_measure(session_key, session_name, measure, index, total):
    prefix = measure['MeasurePrefix']
    number = measure['MeasureNumber']
    title = measure.get('CatchLine') or measure.get('RelatingTo') or ""
    result = []

    if index % LOG_EVERY == 0 or index == 1:
        print(f"    → Measure {index}/{total}: {prefix} {number}")

    try:
        url = (
            f"{BASE_URL}MeasureDocuments?"
            f"$filter=SessionKey eq '{session_key}' and "
            f"MeasurePrefix eq '{prefix}' and "
            f"MeasureNumber eq {number}&$format=json"
        )
        response = requests.get(url)
        response.raise_for_status()
        docs = response.json()['value']
        if docs:
            print(f"      ↳ Found {len(docs)} document(s) for {prefix} {number}")
        for doc in docs:
            if doc.get('DocumentUrl'):
                created_date = doc.get('CreatedDate')
                result.append({
                    "session_name": session_name,
                    "title": f"{prefix} {number} – {title}",
                    "full_url": doc['DocumentUrl'],
                    "created_date": created_date
                })
    except Exception as e:
        print(f"      ⚠️ Document error for {prefix} {number}: {e}")

    return result

# Main collection
records = []
sessions = get_sessions()

for session in sessions:
    begin_date = pd.to_datetime(session['BeginDate'])
    if begin_date.year >= 2015:
        continue

    session_key = session['SessionKey']
    session_name = session['SessionName']
    print(f"\n🔹 Processing session: {session_name}")

    try:
        measures = get_measures(session_key)
        print(f"  Total measures found: {len(measures)}")

        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            futures = [
                executor.submit(process_measure, session_key, session_name, measure, i+1, len(measures))
                for i, measure in enumerate(measures)
            ]
            for future in as_completed(futures):
                result = future.result()
                if result:
                    records.extend(result)

    except Exception as e:
        print(f"  ❌ Measure error for session {session_name}: {e}")

print(f"\n✅ Total records collected: {len(records)}")
df = pd.DataFrame(records)
df.to_csv("text/state-scrapers/or_api_bill_links.csv", index=False)
print("📁 CSV saved: text/state-scrapers/or_api_bill_links.csv")
