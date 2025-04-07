import json
import requests
from bs4 import BeautifulSoup
import datetime
import re
from dateutil.parser import parse

# Utility functions
def write_file(file_name, directory, data):
    with open(f'output/{directory}/{file_name}.json', 'w') as f:
        json.dump(data, f, indent=4)

def is_date(string, fuzzy=False):
    """
    Return whether the string can be interpreted as a date.

    :param string: str, string to check for date
    :param fuzzy: bool, ignore unknown tokens in string if True
    """
    if string in ["1st","2nd","3rd","4th","5th"]:
        return False
    try:
        parse(string, fuzzy=fuzzy)
        return True
    except ValueError:
        return False

def convert_to_date(date_str):
    str_to_return = ""
    str_list = date_str.split("/")
    #do year first
    if int(str_list[-1]) > 25:
        str_to_return += "19"+str_list[-1]
    else:
        str_to_return += "20"+str_list[-1]
    str_to_return += "-"
    #now add 0 before month/day if necessary and add that
    date = ""
    for item in str_list[0:-1]:
        if len(item) == 1:
            date += "0"+item
        else:
            date += item
    str_to_return += date[0:2]+"-"+date[2:]
    return str_to_return

def date_to_yyyymmdd(date_str):
    date_obj = datetime.strptime(date_str, "%m/%d/%y")
    return date_obj.strftime("%Y-%m-%d")

def get_bill_metadata_1997_2001(uuid, session_year, state_bill_id):
    """
    Retrieves the bill title and sponsor from the bill metadata page.
    """
    # Construct the URL for the bill's HTML page.
    url = f"https://le.utah.gov/~{session_year}/htmdoc/hbillhtm/{state_bill_id}.htm"
    to_scrape = requests.get(url)
    soup = BeautifulSoup(to_scrape.content, 'html.parser')
    
    # Example extraction: Assume the bill title is in an <h1> tag.
    header_elt = soup.find('h3')
    header = header_elt.get_text(strip=True).split() if header_elt else None
    split_idx = header.index('--')
    title = " ".join(header[2:split_idx])
    sponsor = " ".join(header[split_idx+1:])

    bill_metadata = {
        "uuid": uuid,
        "state": "UT",
        "session": session_year,  # For these sessions, we use the session year directly.
        "state_bill_id": state_bill_id,
        "title": title,
        "description": None,  # No bill description available for these sessions.
        "status": None,  # Could be derived from history if needed.
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
        "sponsors": [sponsors]

    }
    
    return bill_metadata, sponsors_output

def get_bill_history_1997_2001(uuid, session_year, state_bill_id):
    """
    Retrieves the bill history from the status text file and extracts action dates,
    descriptions, and vote counts (if available).
    """
    # Construct the URL for the status text file.
    status_url = f"https://le.utah.gov/~{session_year}/status/hbillsta/{state_bill_id}.txt"
    response = requests.get(status_url)
    response_text = response.text

    # Regular expression to match dates and descriptions
    date_desc_pattern = r"(\d{1,2}/\d{1,2}/\d{2})\s+([^\n]+)"

    # Find all matches
    matches = re.findall(date_desc_pattern, response_text)

    # History log
    actions = []

    for match in matches:
        date, action = match

        actions.append({
            "date": date_to_yyyymmdd(date),
            "action": action.strip()  # Clean any extra spaces from the action
        })

    bill_history_data = {
        "uuid": uuid,
        "state": state,
        "session": session,
        "state_bill_id": state_bill_id,
        "history": [actions]
    }

    return bill_history_data

def collect_bill_data_1997_2001(uuid, state_bill_id, session_year):
    """
    Base function to collect data for sessions 1997-2001.
    Returns four JSON objects: bill_metadata, sponsors, bill_history, and votes.
    """

    history_data = get_bill_history_1997_2001(uuid, session_year, state_bill_id)

    bill_meta_data, sponsors = get_bill_metadata_1997_2001(uuid, session_year, state_bill_id)
    write_file(uuid, "bill_metadata", bill_meta_data)
    write_file(uuid, "sponsors", sponsors)

    bill_history = {
        "uuid": uuid,
        "state": "UT",
        "session": session_year,
        "state_bill_id": state_bill_id,
        "date": history_data[0],
        "action": history_data[1]
    }

# Example usage:
if __name__ == "__main__":
    # For example, collecting data for HB0104 from 1997.
    bill_data = collect_bill_data_1997_2001("UT1997HB104", "HB0104", "1997")
