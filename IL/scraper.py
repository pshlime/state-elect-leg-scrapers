import requests 
from bs4 import BeautifulSoup
import json
import os

# Function to write JSON to a file
def write_json(data, folder, filename):
  os.makedirs(folder, exist_ok=True)
  with open(os.path.join(folder, filename), "w") as f:
    json.dump(data, f, indent=4)

# Base function to scrape bill data
def scrape_bill(uuid, state, session, state_bill_id):
  # Set base URL depending on session and state
  base_url = f"https://www.ilga.gov/legislation/legisnet{session}/{session}0{state_bill_id}.html" # edit this link
  response = requests.get(base_url)

  if response.status_code != 200:
    print(f"Failed to fetch metadata for {state_bill_id}. URL may not exist.")
    return None

  soup = BeautifulSoup(response.text, "html.parser")
  
  # Step 1: Scrape bill metadata (description, title, etc.)

  # a. Extract Title
  title = soup.find("b").get_text(strip=True) if soup.find("b")

  # b. Extract description
  description_tag = soup.find("p")
  description = description_tag.get_text(strip=True) if description_tag else "N/A"

  # Extract bill status
  status = "N/A"
  status_table = soup.find_all("table")
  if status_table and len(status_table) > 1:
    rows = status_table[1].find_all("tr")
    if rows and len(rows) > 1:
      status = rows[-1].get_text(strip=True) # Last row usually has final status

  metadata = {
    "uuid": uuid,
    "state": state,
    "session": session,
    "state_bill_id": state_bill_id,
    "title": title,
    "description": description,
    "status": status,
    "state_url": base_url
  }

  return metadata

  # Scrape bill sponsors
def scrape_sponsors(uuid, state, session, state_bill_id):
  base_url = f"https://www.ilga.gov/legislation/legisnet{session}/{session}0{state_bill_id}.html"
  response = requests.get(base_url)

  if response.status_code != 200:
    print(f"Failed to fetch sponsors for {state_bill_id}. URL may not exist.")
    return None

  soup = BeautiulSoup(response.text, "html.parser")

  sponsor_sectio = soup.find("b", string="House Sponsors") or soup.find("b", string="Senate Sponsors")
  sponsors_list = []

  if sponsor_section:
    sponsor_text = sponsor_section.find_next("p").get_text(strip=True) if sponsor_section.find_next("p") else "N/A"
    sponsor_names = [s.strip() for s in sponsor_text.split(",")]
    sponsor_list = [{"sponsor_name": name, "sponsor_type": "sponsor"} for name in sponsor_names]

  sponosors = {
    "uuid": uuid,
    "state": state,
    "session": session,
    "state_bill_id": state_bill_id,
    "sponsors": sponsors_list
  }

  return sponsors

# Scrape bill history
def scrape_bill_history(uuid, state, session, state_bill_id):
  history_url = f"https://www.ilga.gov/legislation/legisnet{session}/{session}0{state_bill_id}.html"
  response = requests.get(history_url)

  if response.status_code != 200:
    print (f"Failed to fetch history for {state_bill_id}. URL may not exist.")
    return None

  soup = BeautifulSoup(response.text, "html.parser")
  history_table = soup.find_all("table")[-1]

  bill_history = []
  if history_table:
    rows = history_table.find_all("tr")[1:]
    for row in rows:
      cols = row.find_all("td")
      if len(cols) >= 2:
        date = cols[0].get_text(strip=True)
        action = cols[1].get_text(strip=True)
        bill_history.append({"date": date, "action": action})

  history = {
    "uuid": uuid,
    "state": state,
    "session": session,
    "state_bill_id": state_bill_id,
    "bill_history": bill_hystory
  }

  return history

  # Scrape vote data
def scrape_votes(uuid, state, session, state_bill_id):
  vote_url = f"https://www.ilga.gov/legislation/votehistory/hrollcalls{session}/{session}0{state_bill_id}.html"
  response = requests.get(vote_url)

  if response.status_code != 200:
    print(f"No vote records found for {state_bill_id}.")
    return NOne

  soup = BeautifulSoup(response.text, "html.parser")
  vote_tables = soup.find_all("table")

  votes = []
  if vote_tables:
    for vote_table in vote_tables:
      rows = vote_table.find_all("tr")[1:]
      for row in rows:
        cols = row.find_all("td")
        if len(cols) >= 5:
          vote_event = {
            "chamber": cols[0].get_text(strip=True),
            "date": cols[1].get_text(strip=True),
            "description": cols[2].get_text(strip=True),
            "yeas": int(cols[3].get_text(strip=True)),
            "nays": int(cols[4].get_text(strip=True)),
            "others": int(cols[5].get_text(strip=True)) if len(cols) > 5 else 0
          }
          votes.append(vote_event)
  vote_data = {
    "uuid": uuid,
    "state": state,
    "session": session,
    "state_bill_id": state_bill_id,
    "votes": votes
  }

  return vote_data

  # Organize data into JSON structure
def scrape_bill(uuid, state, session, state_bill_id):
  output_folder = f"{state}/output"

  metadata = scrape_bill_metadata(uuid, state, session, state_bill_id)
  if metadata:
    write_json(metadata, f"{output_folder}/bill_metadata", f"{uuid}.json")
  
  sponsors = scrape_sponsors(uuid, state, session, state_bill_id)
  if sponsors:
    write_json(sponsors, f"{output_folder}/sponsors", f"{uuid}.json")

  history = scrape_bill_history(uuid, state, session, state_bill_id)
  if history:
    write_json(history, f"{output_folder}/bill_history", f"{uuid}.json")

  votes = scrape_votes(uuid, state, session, state_bill_id)
  if votes:
    for vote in votes["votes"]:
      vote_filename = f"{uuid}_{vote['date"].replace("-", "")}.json"
      write_json(vote, f"{output_folder}/votes", vote_filename)

  print(f"Scraping completed for {state_bill_id}.")
                                
# Example call
scrape_bill("IL1995HB2576", "IL", "89", "HB2576")



               
