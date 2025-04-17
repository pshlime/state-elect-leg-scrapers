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

def get_action_type(action_types, actual_action):
    action_type = ""
    for type in action_types.split():
        if type in actual_action:
            if "read" in actual_action and "1st" in actual_action:
                return "Introduced"
            else:
                action_type += type
    if not action_type:
        return "N/A"
    return action_type

def get_status(soup):
    last_action_line = soup.find(string=lambda s: s and "Last Action:" in s)
    if last_action_line:
        last_action = last_action_line.strip()
    else: 
        return "Last Action not found."
    flags = {"struck":"Defeated - ","signed":"Enacted - "}
    for flag in flags.keys():
        if flag in last_action:
            return flags[flag]
    return f"{last_action.split()[-1]} - "
    
#bill functions

def get_bill_metadata_1997_2001(uuid, session_year, state_bill_id):
    """
    Retrieves the bill title and sponsor from the bill metadata page.
    """
    # Construct the URL for the bill's HTML page.
    if session_year == "1997":
        url = f"https://le.utah.gov/~{session_year}/htmdoc/hbillhtm/{state_bill_id}.htm"
    else:
        url = f"https://le.utah.gov/~{session_year}/htmdoc/Hbillhtm/{state_bill_id}.htm"
    to_scrape = requests.get(url)
    soup = BeautifulSoup(to_scrape.content, 'html.parser')
    
    header_elt = soup.find('h3')
    header = header_elt.get_text(strip=True).split() if header_elt else None
    split_idx = header.index('--')
    title = " ".join(header[2:split_idx])
    sponsor = " ".join(header[split_idx+1:])
    status = get_status(soup)


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
        "sponsor_name": sponsor,
        "sponsor_type": "sponsor",
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
    # Construct the URL for the status text file.
    status_url = f"https://le.utah.gov/~{session_year}/status/hbillsta/{state_bill_id}.txt"
    
    response = requests.get(status_url)
    text_data = response.text
   
    pattern = r"(\d{2}/\d{2}/\d{2})\s+(.+)"
    matches = re.findall(pattern, text_data)
    actions = [{"date": convert_date(match[0]), "action": " ".join(match[1].split())} for match in matches]
                
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
    write_file(uuid, "bill_metadata", metadata)
    write_file(uuid, "sponsors", sponsors)
        
    history_data = get_bill_history_1997_2001(uuid, session_year, state_bill_id)    
    write_file(uuid, "bill_history", history_data)
    return {"bill_metadata":metadata,"sponsors":sponsors,"bill_history":history_data}
    

# Example usage:
if __name__ == "__main__":
    # For example, collecting data for HB0104 from 1997.
    bill_data = collect_bill_data_1997_2001("UT2000H8", "2000", "HB0008")