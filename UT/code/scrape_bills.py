import json
import requests
from bs4 import BeautifulSoup
from dateutil.parser import parse
import re
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed
import pandas as pd
import logging
import os

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

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
        last_action = last_action.replace("Last Action: ", "")
    else: 
        return "Last Action not found."
    flags = {"struck":"Defeated - {last_action}","signed":"Enacted - {last_action}",}
    for flag in flags.keys():
        if flag in last_action:
            return flags[flag].format(last_action=last_action)
    return last_action
    

#bill functions
def get_bill_metadata_1997_2001(uuid, session_year, state_bill_id):
    """
    Retrieves the bill title and sponsor from the bill metadata page.
    """
    # Construct the URL for the bill's HTML page.
    if state_bill_id.upper().startswith(("SB", "SR", "SJR")):
        bill_folder = "sbillhtm" if session_year == "1997" else "Sbillhtm"
    else:
        bill_folder = "hbillhtm" if session_year == "1997" else "Hbillhtm"

    url = f"https://le.utah.gov/~{session_year}/htmdoc/{bill_folder}/{state_bill_id}.htm"
    
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
    
    return bill_metadata,sponsors_output,url
  
def get_bill_metadata_2002(uuid, session_year, state_bill_id):
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
    last_action = re.search(r"Last Action:.*?(?=Last Location)", last_action_li.get_text(strip=True))
    last_action = str(last_action) # added this because of an error i was getting, i think it's fixed?
    last_action = last_action.replace("Last Action:", "").strip()
    
    status = "Enacted - {last_action}".format(last_action = last_action) if any("Signed" in chunk for chunk in last_action) else last_action

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
        "sponsor_name": sponsor1.replace("Rep. ", "").replace("Sen. ", ""),
        "sponsor_type": "sponsor",
    })
    if sponsor2:
        sponsors.append({
            "sponsor_name": sponsor2.replace("Rep. ", "").replace("Sen. ", ""),
            "sponsor_type": "sponsor",
        })

    sponsors_output = {
        "uuid": uuid,
        "state": "UT",
        "session": session_year,
        "state_bill_id": state_bill_id,
        "sponsors": sponsors
    }
    
    return bill_metadata,sponsors_output,url
          

def get_bill_history_1997_2001(uuid, session_year, state_bill_id):
    """
    Retrieves the bill history from the status text file and extracts action dates,
    descriptions, and vote counts (if available).
    """
    # Construct the URL for the status text file.
    if state_bill_id.upper().startswith(("SB", "SR", "SJR")):
        status_folder = "sbillsta"
    else:
        status_folder = "hbillsta"
    status_url = f"https://le.utah.gov/~{session_year}/status/{status_folder}/{state_bill_id}.txt"
    
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

def get_bill_history_2002(uuid, session_year, state_bill_id):
    """
    Retrieves the bill history from the status text file and extracts action dates,
    descriptions, and vote counts (if available).
    """
    if state_bill_id.upper().startswith(("SB", "SR", "SJR")):
        status_folder = "sbillsta"
    else:
        status_folder = "hbillsta"

    # Construct the status URL
    status_url = f"https://le.utah.gov/~{session_year}/status/{status_folder}/{state_bill_id}.txt"
    
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

def extract_names_by_label(soup, label_start):
    """Find names listed under a label like 'Yeas', 'Nays', etc."""
    label_tag = soup.find('b', string=lambda s: s and s.strip().startswith(label_start))
    if not label_tag:
        return []

    table_tag = label_tag.find_next('table')
    if not table_tag:
        return []

    # Find all <td> elements inside the table and extract the text
    names = [td.get_text(strip=True) for td in table_tag.find_all('td')]
    return names

def extract_vote_lists(html_content):
    # Initialize lists to store the votes
    yeas = []
    nays = []
    absent = []
    
    # First, clean any HTML tags from the content
    clean_content = re.sub(r'<[^>]+>', '', html_content)
    
    # Find the YEAS, NAYS, and ABSENT sections
    yeas_section = re.search(r'YEAS \d+\s+(.*?)(?=\s+NAYS \d+)', clean_content, re.DOTALL)
    nays_section = re.search(r'NAYS \d+\s+(.*?)(?=\s+ABSENT \d+)', clean_content, re.DOTALL)
    absent_section = re.search(r'ABSENT \d+\s+(.*?)$', clean_content, re.DOTALL)
    
    # Function to process a section of text and extract names
    def extract_names(text):
        names = []
        if text:
            # Split into lines
            lines = [line.strip() for line in text.split('\n') if line.strip()]
            
            for line in lines:
                # Split the line by multiple spaces (2 or more)
                name_parts = [part.strip() for part in re.split(r'\s{2,}', line) if part.strip()]
                
                # Add valid names to the list
                for name in name_parts:
                    # Ensure it looks like a name (capitalized word)
                    if re.match(r'^[A-Z][a-z]+', name):
                        names.append(name)
        
        return names
    
    # Process each section
    if yeas_section:
        yeas = extract_names(yeas_section.group(1))
    
    if nays_section:
        nays = extract_names(nays_section.group(1))
    
    if absent_section:
        absent = extract_names(absent_section.group(1))
    
    return {
        'yeas': yeas,
        'nays': nays,
        'absent': absent
    }

def get_votes(uuid,url, session_year,state_bill_id):
    response = requests.get(url)
    soup = BeautifulSoup(response.content, 'html.parser')
    links = soup.select("#billStatus a")
    links = [a['href'] for a in links if 'href' in a.attrs]

    if int(session_year) <= 2011:
        links = [f"https://le.utah.gov{link}" for link in links if "billsta" in link]
        count = 1
        for link in links:
            response = requests.get(link)
            text_data = response.text.split()
            
            chamber = 'H' if 'h.txt' in link else 'S'
            months = {"JANUARY":"01","FEBRUARY":"02","MARCH":"03","APRIL":"04","MAY":"05","JUNE":"06","JULY":"07",
                    "AUGUST":"08","SEPTEMBER":"09","OCTOBER":"10","NOVEMBER":"11","DECEMBER":"12"}
            
            if 'h.txt' in link:
                desc_idx = text_data.index("TABULATION")+1
                description = ""
                while text_data[desc_idx] not in months.keys():
                    description += text_data[desc_idx] + " "
                    desc_idx += 1
                
                #get date
                date = text_data[desc_idx+2] + "-" + months[text_data[desc_idx]] + "-" + text_data[desc_idx+1]

                #vote info
                yeas = text_data[text_data.index("YEAS")+2]
                nays = text_data[text_data.index("NAYS")+2]
                other = text_data[text_data.index("VOTING")+2]

                #getting roll call
                roll_call = []
                roll_idx = text_data.index("YEAS")+3
                r= "Yea"
                while roll_idx <= len(text_data)-1:
                    if text_data[roll_idx] == "NAYS":
                        roll_idx += 3
                        r = "Nay"
                    if text_data[roll_idx] == "ABSENT":
                        roll_idx += 6
                        r = "Absent"
                    
                    roll_call.append({
                        "name": text_data[roll_idx],
                        "response": r
                    })
                    roll_idx +=1
            else:
                date_pattern = re.compile(r'\d{1,2}/\d{1,2}/\d{4}')

                # Extract date
                date = next((item for item in text_data if date_pattern.fullmatch(item)), None)
                date = datetime.strptime(date, "%m/%d/%Y").strftime("%Y-%m-%d")

                # Extract description
                pattern = re.search(r'(PASSAGE.*?)\s+\d{1,2}/\d{1,2}/\d{4}.*?\n(.*Reading)', response.text, re.IGNORECASE)
                if pattern:
                    description = f"{pattern.group(1).strip()} - {pattern.group(2).strip()}"
                else:
                    description = ""

                votes = extract_vote_lists(response.text)
                yeas = votes['yeas']
                nays = votes['nays']
                other = votes['absent']
                
                roll_call = []
                roll_call.extend([{"name": name, "response": "Yea"} for name in yeas])
                roll_call.extend([{"name": name, "response": "Nay"} for name in nays])
                roll_call.extend([{"name": name, "response": "Absent"} for name in other])

                yeas = len(yeas)
                nays = len(nays)
                other = len(other)

            votes = {
                "uuid": uuid,
                "state": "UT",
                "session": session_year,  
                "state_bill_id": state_bill_id,
                "chamber": chamber,
                "date": date, 
                "description": description,
                "yeas": yeas,
                "nays":nays,
                "other":other,
                "roll_call": [roll_call]
            }

            file_name = f"{uuid}_{count}"
            write_file(file_name,"votes",votes)

            count += 1
    else:
        links = [f"https://le.utah.gov{link}" for link in links if "DynaBill" in link]
        count = 1
        for link in links:
            response = requests.get(link)
            soup = BeautifulSoup(response.content, 'html.parser')
            if "voice vote" in soup.text:
                continue
            else:
                chamber = "H" if 'house = "H' in link else "S"
                date = soup.find("b").get_text()
                match = re.search(r'(\d{1,2}/\d{1,2}/\d{4})', date)
                if match:
                    raw_date = match.group(1)  # e.g., "2/24/2014"
                    # Convert to YYYY-MM-DD
                    date = datetime.strptime(raw_date, "%m/%d/%Y").strftime("%Y-%m-%d")

                centers = soup.find_all('center')
                description = ' - '.join([centers[5].get_text(strip=True), centers[6].get_text(strip=True)])

                yeas = extract_names_by_label(soup, "Yeas")
                nays = extract_names_by_label(soup, "Nays")
                other = extract_names_by_label(soup, "Absent")

                roll_call = []
                roll_call.extend([{"name": name, "response": "Yea"} for name in yeas])
                roll_call.extend([{"name": name, "response": "Nay"} for name in nays])
                roll_call.extend([{"name": name, "response": "Absent"} for name in other])
                votes = {
                    "uuid": uuid,
                    "state": "UT",
                    "session": session_year,  
                    "state_bill_id": state_bill_id,
                    "chamber": chamber,
                    "date": date, 
                    "description": description,
                    "yeas": len(yeas),
                    "nays": len(nays),
                    "other": len(other),
                    "roll_call": [roll_call]
                }

                file_name = f"{uuid}_{count}"
                write_file(file_name,"votes",votes)

                count += 1
   

#main function
def collect_bill_data(uuid, session_year, state_bill_id):
    """
    Base function to collect data for sessions 1997-2001.
    Returns four JSON objects: bill_metadata, sponsors, bill_history, and votes.
    """
    if int(session_year) >= 2002:
        metadata,sponsors,url = get_bill_metadata_2002(uuid,session_year, state_bill_id)
        write_file(uuid, "bill_metadata", metadata)
        write_file(uuid, "sponsors", sponsors)
            
        history_data = get_bill_history_2002(uuid, session_year, state_bill_id)    
        write_file(uuid, "bill_history", history_data)
        get_votes(uuid,url, session_year,state_bill_id)
    elif int(session_year) < 2002:
        metadata,sponsors,url = get_bill_metadata_1997_2001(uuid,session_year, state_bill_id)
        write_file(uuid, "bill_metadata", metadata)
        write_file(uuid, "sponsors", sponsors)
            
        history_data = get_bill_history_1997_2001(uuid, session_year, state_bill_id)    
        write_file(uuid, "bill_history", history_data)
        
# Example usage:
if __name__ == "__main__":
    bill_list = pd.read_csv("UT/output/UT_bills_to_process.csv")
    metadata_dir = "UT/output/bill_metadata"
    existing_uuids = {filename.removesuffix(".json") for filename in os.listdir(metadata_dir)}

    # Exclude bills that have already been processed
    bill_list = bill_list[~bill_list["UUID"].isin(existing_uuids)]

    bill_rows = bill_list[["UUID", "session", "bill_number"]].to_dict(orient="records")
    # Parallel execution
    with ThreadPoolExecutor(max_workers=10) as executor:
        futures = {
            executor.submit(collect_bill_data, row["UUID"], row["session"], row["bill_number"]): row
            for row in bill_rows
        }

    for future in as_completed(futures):
        row = futures[future]
        try:
            result = future.result()
            # Do something with result, e.g. collect it if scrape_bill returns data
            # results.append(result)
        except Exception as exc:
            logging.error(f"Bill {row} generated an exception: {exc}")
