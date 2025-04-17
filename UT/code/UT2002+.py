import json
import requests
from bs4 import BeautifulSoup
from dateutil.parser import parse
import re
from datetime import datetime

#helper functions
def write_file(file_name, directory, data):
    with open(f'UT/output/{directory}/{file_name}.json', 'w') as f:
        json.dump(data, f, indent=4)

def convert_date(date_str):
    date_obj = datetime.strptime(date_str, "%m/%d/%y")
    return date_obj.strftime("%Y-%m-%d")

#bill functions

def get_bill_metadata_1997_2001(uuid, session_year, state_bill_id):
    """
    Retrieves the bill title and sponsor from the bill metadata page.
    """
    # Construct the URL for the bill's HTML page.
    url = f"https://le.utah.gov/~{session_year}/bills/static/{state_bill_id}.html"
    to_scrape = requests.get(url)
    soup = BeautifulSoup(to_scrape.content, 'html.parser')

    #get title
    header_elt = soup.find('h3')
    header = header_elt.get_text(strip=True).split()[2:] if header_elt else None
    title = " ".join(header)

    #get sponsor
    bill_sponsor_div = soup.find('div', id='billsponsordiv')
    floor_sponsor_div = soup.find('div', id='floorsponsordiv')
    sponsor1 = bill_sponsor_div.get_text(strip=True).replace("Bill Sponsor:", "") if bill_sponsor_div else None
    sponsor2 = floor_sponsor_div.get_text(strip=True).replace("Floor Sponsor:", "") if floor_sponsor_div else None
 
    #get status
    last_action_li = soup.select_one('ul.billinfoulm li:contains("Last Action")')
    last_action = last_action_li.get_text(strip=True).replace("Last Action:", "").split()
    status = "Enacted - " if any("Signed" in chunk for chunk in last_action) else last_action[4][:-4]

    bill_metadata = {
        "uuid": uuid,
        "state": "UT",
        "session": session_year,  
        "state_bill_id": state_bill_id,
        "title": title,
        "description": None, 
        "status": status,
        "state_url": url
    }

    sponsors = []
    sponsors.append({
        "sponsor_name": [sponsor1,sponsor2],
        "sponsor_type": ["Bill Sponsor","Floor Sponsor"],
    })
    sponsors_output = {
        "uuid": uuid,
        "state": "UT",
        "session": session_year,
        "state_bill_id": state_bill_id,
        "sponsors": sponsors
    }
    
    return bill_metadata,sponsors_output
       

def get_bill_history_1997_2001(uuid, session_year, state_bill_id):
    """
    Retrieves the bill history from the status text file and extracts action dates,
    descriptions, and vote counts (if available).
    """
    status_url = f"https://le.utah.gov/~{session_year}/status/hbillsta/{state_bill_id}.txt"
    
    response = requests.get(status_url)
    text_data = response.text
   
    pattern = r"(\d{2}/\d{2}/\d{2})\s+(.+)"
    matches = re.findall(pattern, text_data)
    actions = [{"date": convert_date(match[0]), "action": " ".join(match[1].split()[:-1])} for match in matches]
    
    print(actions)

    bill_history = {
        "uuid": uuid,
        "state": "UT",
        "session": session_year,
        "state_bill_id": state_bill_id,
        "bill_history": [actions]
    }
    return bill_history

#main function
def collect_bill_data_1997_2001(uuid, session_year, state_bill_id):
    """
    Base function to collect data for sessions 1997-2001.
    Returns four JSON objects: bill_metadata, sponsors, bill_history, and votes.
    """
    metadata,sponsors = get_bill_metadata_1997_2001(uuid,session_year, state_bill_id)
    # write_file(uuid, "bill_metadata", metadata)
    # write_file(uuid, "sponsors", sponsors)
        
    history_data = get_bill_history_1997_2001(uuid, session_year, state_bill_id)    
    # write_file(uuid, "bill_history", history_data)
    return {"bill_metadata":metadata,"sponsors":sponsors,"bill_history":history_data}
    

# Example usage:
if __name__ == "__main__":
    bill_data = collect_bill_data_1997_2001("UT2020HB0019", "2020", "HB0019")