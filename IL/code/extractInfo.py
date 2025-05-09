#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Sun Apr 13 11:58:22 2025

@author: ivywang
"""

import csv
import re
import requests
from bs4 import BeautifulSoup
from datetime import datetime
import json

def scrape_bill(uuid, session, bill_number):
    #bill_history_data, las
    
    state = uuid[0:2]
    year = uuid[2:6]
    state_bill_id = bill_number
    bill_id = state_bill_id[0:2] + "-" + state_bill_id[2:] #make it work with old function
    metadata_record = {}
    sponsor_record = {}
    vote_record = {}
    bill_record = {}
    
    # Generate the history URL
    history_url, roll_call_url, status_url= generate_history_url(bill_id, session)
    
    # Extract bill meta_data
    bill_title, bill_description, bill_status = extractMetadata(history_url)
    if bill_title:
        metadata_record = {"uuid":uuid, "state":state, "session":year,
              "state_bill_id":state_bill_id, "title":bill_title, 
              "description":bill_description, "status":bill_status, "state_url":history_url} 
        write_file(uuid, "bill_metadata", metadata_record)
    
    
    # Extract sponsors
    sponsor_list = extractSponsors(history_url)
    if sponsor_list:
        sponsor_record = {"uuid":uuid, "state":state, "session":year,
              "state_bill_id":state_bill_id, "sponsors":sponsor_list}
        write_file(uuid, "sponsors", sponsor_record) 
    
    
    # Extract votes
    voteHistory = extractVotes(roll_call_url)
    
    if voteHistory:
        # unpack vote history (there could be multiple rounds of voting)
        # each voteHistory element contans [final_votes, roll_call, vote_date, chamber, vote_description]) 
        for vh in voteHistory:
            vote_record = {"uuid":uuid, "state":state, "session":year,
                  "state_bill_id":state_bill_id, "chamber":vh[3], "date":vh[2],
                  "description": vh[4], "Yea":vh[0]["yeas"], "Nay":vh[0]["nays"],
                  "NV":vh[0]["other"], "roll_call":vh[1]}
            filename = uuid + "_" + vh[2].replace("-", "")
            write_file(filename, "votes", vote_record)     
        
    # Extract bill history
    bill_actions = extractHistory(status_url)
    if bill_actions:
        bill_record = {"uuid":uuid, "state":state, "session":year,
              "state_bill_id":state_bill_id, "bill_history":bill_actions}
        write_file(uuid, "bill_history", bill_record)    

    #return json.dumps([metadata_record, sponsor_record, vote_record, bill_record])  


def extractMetadata(url):
    bill_title = ""
    bill_description = ""
    bill_status = ""
    
    result = requests.get(url)
    
    if result:
        doc = BeautifulSoup(result.text, "html.parser")
        # extract title of the bill
        em_tag = doc.find("em", string=re.compile("Short"))
        if em_tag:
            bill_title = em_tag.next_sibling.strip()
        
        # extract description of the bill
        em_tag = doc.find("em", string=re.compile("Synopsis"))
        if em_tag:
            bill_description = em_tag.next_sibling.strip()
            bill_description = bill_description.replace("\r", "")
            bill_description = bill_description.replace("\n", "")
            bill_description = re.sub(r'\s+', ' ', bill_description).strip()

        # extract status of the bill
        em_tag = doc.find("em", string=re.compile("Last action on Bill"))
        if em_tag:
            bill_status = em_tag.next_sibling.strip()
        
    return bill_title, bill_description, bill_status
    
    
def extractHistory(url):
    bill_history = []
    
    result = requests.get(url)
    if result:
        doc = BeautifulSoup(result.text, "html.parser")
        pattern_date_letter = r"[A-Za-z]{3}-\d{2}-\d{4}"
        pattern_date_number = r"\d{2}-\d{2}-\d{2}"
        
        # looking for rows that start with pattern like JAN-01-2001
        action_text = doc.find_all(string=re.compile(pattern_date_letter))
        
        
        if action_text:  
            for element in action_text[0].split("\n"):
                bill_record = {}
                match_date = re.findall(pattern_date_letter, element)
                if match_date:
                    date_string = match_date[0]
                    date_object = datetime.strptime(date_string, "%b-%d-%Y")
                    new_date_string = date_object.strftime("%Y-%m-%d")
                    action = element.strip()[len(date_string):].strip()
                    bill_record["date"] = new_date_string
                    bill_record["action"] = re.sub(r'\s+', ' ', action).strip() # Replace one or more whitespace characters with a single space
                    bill_history.append(bill_record)
                    
        # looking for rows that start with pattern like 98-01-22            
        action_text = doc.find_all(string=re.compile(pattern_date_number))
        

        if action_text:
            for element in action_text[0].split("\n"):
                bill_record = {}
                match_date = re.findall(pattern_date_number, element)
                if match_date:
                    date_string = match_date[0]
                    date_object = datetime.strptime(date_string, "%y-%m-%d")
                    new_date_string = date_object.strftime("%Y-%m-%d")
                    action = element.strip()[len(date_string):].strip()
                    bill_record["date"] = new_date_string
                    bill_record["action"] = re.sub(r'\s+', ' ', action).strip() # Replace one or more whitespace characters with a single space
                    bill_history.append(bill_record)
                    
        return bill_history
    
def extractSponsors(url):
    sponsor_list = []
    isFirstSponsor = True
    
    result = requests.get(url)
    if result:
        doc = BeautifulSoup(result.text, "html.parser")
        # extract sponsors of the bill
        pre_tag = doc.find('pre')
        if pre_tag:
            sponsor_links = pre_tag.find_all("a", href=lambda x: 'sponsor' in x if x else False)
            for sponsor in sponsor_links:
                sponsor_add = sponsor.text.strip().lower().capitalize()
                if sponsor_add:
                    sponsor_dict = {}
                    sponsor_dict["sponsor_name"] = sponsor_add
                    # treating the first sponsor as sponsor and the rest as cosponsors
                    # to-do: separating house sponsors from senate sponsors
                    if isFirstSponsor == True:
                        sponsor_dict["sponsor_type"] = "sponsor"
                        isFirstSponsor = False
                    else:
                        sponsor_dict["sponsor_type"] = "cosponsor"
                    
                    sponsor_list.append(sponsor_dict)
    return sponsor_list


# Function to extract votes and roll call 
def extractVotes(url):
    pattern_total = r".*YEAS.*NAYS.*"
    pattern_individual = r"([YN])\s+([A-Z]+)+"
    pattern_date = r"\d{1,2}\/\d{1,2}\/\d{4}"
    pattern_chamber = r".*ROLL.*CALL"
    chamber_mapping = {"house":"H", "senate":"S"}
    voteHistory = []
    roll_call = []
    final_votes = {}
    vote_date = ""
    chamber = ""
    vote_description = ""
    votelinks = []
    
    result = requests.get(url)
    if result:
        doc = BeautifulSoup(result.text, "html.parser")
        
        #find all bill vote links on this page
        votelinks = doc.find_all('a', href=True) 
        for pagelink in votelinks:    
            baseurl = url.rsplit('/', 1)[0]
            newurl = baseurl + "/" + pagelink['href']
            
            # match date which is stored in the <a href> tage
            date_found = re.findall(pattern_date, pagelink.string)
            if date_found:    
                date_split = date_found[0].split("/")
                vote_date = date_split[2] + "-" + date_split[0] + "-" + date_split[1]
            
            billVoteResult = requests.get(newurl)
            # Split the content into lines
            lines = billVoteResult.text.splitlines()

            # Return the seventh line if it exists
            if len(lines) >= 10:
                vote_description = lines[9].strip()
                        
            doc = BeautifulSoup(billVoteResult.text, "html.parser")
            votes = doc.find("p", string=re.compile("YEAS"))
            for element in votes.string.split("\n"):
                # match chamber
                match_chamber = re.findall(pattern_chamber, element)
                if match_chamber:
                    chamber = match_chamber[0].split()[0]
                    chamber = chamber_mapping[chamber.lower()]
             
                # match total votes
                match_total = re.search(pattern_total, element)
                if match_total:
                    pairs_total = dict(re.findall(r'(\d+)\s+([A-Z]+)', match_total.group()))
                    final_votes = {v:int(k) for k, v in pairs_total.items()}
                    
                    # in case any of YEAS, NAYS, PRESENT is missing from the page. 
                    final_votes.setdefault("YEAS", 0)
                    final_votes.setdefault("NAYS", 0)
                    final_votes.setdefault("PRESENT", 0)

                    # Changing key name to be consistent with other states per Joe's comment
                    final_votes["yeas"] = final_votes.pop("YEAS")
                    final_votes["nays"] = final_votes.pop("NAYS")
                    final_votes["other"] = final_votes.pop("PRESENT")
                    
                # match individual votes
                match_individual = re.findall(pattern_individual, element)
                if match_individual:
                    for element in match_individual:
                        response = ""
                        if element[0] == "Y":
                            response = "Yea"
                        elif element[0] == "N":
                            response = "Nay"
                        elif element[0] == "E":
                            response = "NV"
                        roll_call.append({"name":element[1].capitalize(), "response":response})
            voteHistory.append([final_votes, roll_call, vote_date, chamber, vote_description])                       
    else:
        #print(f"⚠️ Warning: {url} is broken. Skipping.")
        return None, None, None, None

    return voteHistory

# Function to generate the history URL with padded bill number
def generate_history_url(bill_id, session):
    # Split the bill ID by hyphen, e.g. 'SB-231' -> ['SB', '231']
    parts = bill_id.split('-')
    if len(parts) != 2:
        print(f"⚠️ Warning: Invalid bill_id format '{bill_id}' — skipping.")
        return None, None, None # or raise an error or return a placeholder URL
    
    bill_type = parts[0] # 'SB' or 'HB' 
    bill_number = parts[1]  # '231', '15', etc.

    # Ensure that the session is properly formatted (2 digits with a leading zero if needed)
    session_str = str(session).zfill(2)  # e.g., '90' for session 90

    # Pad the bill number with leading zeros to make sure it's always 4 digits
    padded_bill_number = bill_number.zfill(4)  # e.g., '0231' for '231' and '0015' for '15'

    # Generate the state bill ID in the desired format (e.g., 'SB0231', 'HB0015')
    state_bill_id = f"{bill_type}{padded_bill_number}"

    # Construct the history URL
    history_url = f"https://www.ilga.gov/legislation/legisnet{session_str}/summary/{session_str}0{state_bill_id}.html"
    roll_call_url = f"https://www.ilga.gov/legislation/votehistory/hrollcalls{session_str}/{session_str}0{state_bill_id}.html"
    status_url = f"https://www.ilga.gov/legislation/legisnet{session_str}/status/{session_str}0{state_bill_id}.html"

    return history_url, roll_call_url, status_url

# write extracted info to a file
def write_file(file_name, directory, data):
    with open(f'IL/output/{directory}/{file_name}.json', 'w') as f:
        json.dump(data, f, indent=4)
        
# Example usage
if __name__ == "__main__":
    #print(scrape_bill("IL1997SB504", "90", "504"))
    #(scrape_bill("IL1999HB100", "91", "100"))
    #roll_call_url = "https://www.ilga.gov/legislation/votehistory/hrollcalls91/910HB1234.html"
    #roll_call_url = "https://www.ilga.gov/legislation/votehistory/hrollcalls91/910HB0100.html"

    #voteHistory = extractVotes(roll_call_url)
    uuid = "IL1999H1234"
    session = 91
    bill_number = "HB1234"
    
    scrape_bill(uuid, session, bill_number)
