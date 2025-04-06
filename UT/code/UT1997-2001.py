import json
import requests
from bs4 import BeautifulSoup
import datetime
from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from webdriver_manager.chrome import ChromeDriverManager
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

def get_bill_metadata_1997_2001(session_year, state_bill_id):
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

    bill_metadata = {
        "uuid": f"UT{session_year}{state_bill_id}",
        "state": "UT",
        "session": session_year,  # For these sessions, we use the session year directly.
        "state_bill_id": state_bill_id,
        "title": title,
        "description": None,  # No bill description available for these sessions.
        "status": None,  # Could be derived from history if needed.
        "state_url": url
    }
    
    return bill_metadata

def get_bill_sponsors_1997_2001(session_year, state_bill_id):
    metadata = get_bill_metadata_1997_2001(session_year, state_bill_id)

    sponsor_url = f"https://le.utah.gov/~{session_year}/reports/sponbill.htm#C"
    to_scrape = requests.get(sponsor_url)
    soup = BeautifulSoup(to_scrape.content, 'html.parser')

    # Set up Selenium with Chrome
    options = webdriver.ChromeOptions()
    options.add_argument("--headless")  # Runs Chrome in headless mode (no UI)
    options.add_argument("--disable-gpu")
    options.add_argument("--no-sandbox")

    # Initialize the WebDriver
    driver = webdriver.Chrome(service=Service(ChromeDriverManager().install()), options=options)

    # URL of the Utah legislature page
    url = "https://le.utah.gov/~1997/reports/sponbill.htm"
    driver.get(url)

    # Wait for elements to load
    WebDriverWait(driver, 10).until(EC.presence_of_all_elements_located((By.TAG_NAME, "h4")))

    # Find all sponsor names (h4 elements)
    sponsor_elements = driver.find_elements(By.TAG_NAME, "h4")

    sponsor_data = {}

    for sponsor in sponsor_elements:
        sponsor_name = sponsor.text.strip()
        bills = []

        # Get the next <ul> sibling (which contains bill <li> elements)
        ul_element = sponsor.find_element(By.XPATH, "following-sibling::ul")

        if ul_element:
            # Find all <a> elements inside the <ul>
            bill_links = ul_element.find_elements(By.TAG_NAME, "a")
            for bill in bill_links:
                bill_number = bill.text.strip("[]")  # Remove brackets
                bills.append(bill_number)

        # Only add sponsors with bills
        if bills:
            sponsor_data[sponsor_name] = bills

    # Close the browser session
    driver.quit()

    # Print the results
    for sponsor, bills in sponsor_data.items():
        print(f"{sponsor}: {', '.join(bills)}")


    sponsors = {
        "uuid": metadata[0]["uuid"],
        "state": metadata[0]["state"],
        "session": session_year,
        "state_bill_id": state_bill_id,
        "sponsors": []
    }
    return sponsors

from dateutil.parser import parse

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


def get_bill_history_1997_2001(session_year, state_bill_id):
    """
    Retrieves the bill history from the status text file and extracts action dates,
    descriptions, and vote counts (if available).
    """
    # Construct the URL for the status text file.
    status_url = f"https://le.utah.gov/~{session_year}/status/hbillsta/{state_bill_id}.txt"
    response = requests.get(status_url)
    text_data = response.text
    text_list = text_data.split()
    sponsor = get_bill_metadata_1997_2001(session_year, state_bill_id)[1]

    start = text_list.index(f"{sponsor[-2:]})")
    date = []
    action = []
    act = []
    for unit in text_list[start+1:]:
        if is_date(unit):
            date.append(convert_to_date(unit))
            if act:
                action.append(" ".join(act[:-1]))#cuts off the last thing bc idk what it is
                act=[]
        else:
           act.append(unit)
    
    return date,action


def collect_bill_data_1997_2001(uuid, session_year, state_bill_id):
    """
    Base function to collect data for sessions 1997-2001.
    Returns four JSON objects: bill_metadata, sponsors, bill_history, and votes.
    """
    bill_meta_data = get_bill_metadata_1997_2001(session_year, state_bill_id)
    write_file(uuid, "bill_metadata", bill_meta_data)

    sponsors = get_bill_sponsors_1997_2001(session_year, state_bill_id)

    history_data = get_bill_history_1997_2001(session_year, state_bill_id)    
    
    bill_history = {
        "uuid": uuid,
        "state": "UT",
        "session": session_year,
        "state_bill_id": state_bill_id,
        "date": history_data[0],
        "action": history_data[1]
    }
        
    return {
        "bill_metadata": meta,
        "sponsors": sponsors,
        "bill_history": bill_history,
    }

def write_file(file_name, directory, data):
    with open(f'output/{directory}/{file_name}.json', 'w') as f:
        json.dump(data, f, indent=4)

# Example usage:
if __name__ == "__main__":
    # For example, collecting data for HB0104 from 1997.
    bill_data = collect_bill_data_1997_2001("UT1997HB104", "1997", "HB0104")
