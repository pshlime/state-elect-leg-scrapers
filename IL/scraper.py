#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Sun Apr 13 11:58:22 2025

@author: ivywang
"""
from extractInfo import *
import csv
import requests
from bs4 import BeautifulSoup
import json

billfile_IL = "ILBillList.csv"
bill_metadata_json = "bill_metadata.json"
sponsors_json = "sponsors.json"
votes_json = "votes.json"
bill_history_json = "bill_history.json"
state = "IL"

bill_metadata = []
sponsors = []
votes = []
bill_history = []

with open(billfile_IL, newline='') as csvfile:
    csvreader = csv.reader(csvfile, delimiter=',')
    next(csvreader)
    for row in csvreader:
        if len(row) >= 2:
            # Extract the session and bill ID
            session = row[0].split('-')[1]  # Extract the session from the first column (e.g., '90' from '1997-90')
            year = row[0].split("-")[0]
            bill_id = row[1]  # Bill ID (e.g., 'SB-231')
            state_bill_id = bill_id.replace("-", "")
            uuid = f"{state}{year}{state_bill_id}"
            
            # Generate the history URL
            history_url, roll_call_url, status_url= generate_history_url(bill_id, session)
            
            # Extract bill meta_data
            bill_title, bill_description, bill_status = extractMetadata(history_url)
            if bill_title:
                metadata_record = {"uuid":uuid, "state":state, "session":year,
                      "state_bill_id":state_bill_id, "title":bill_title, 
                      "description":bill_description, "status":bill_status, "state_url":history_url}
                bill_metadata.append(metadata_record)
           
            # Extract sponsors
            sponsor_list = extractSponsors(history_url)
            if sponsor_list:
                sponsor_record = {"uuid":uuid, "state":state, "session":year,
                      "state_bill_id":state_bill_id, "sponsors":sponsor_list}
                sponsors.append(sponsor_record)
            
            # Extract votes
            final_votes, roll_call, vote_date, chamber = extractVotes(roll_call_url)
            if final_votes:
                # description is missing. need to figure out how to get that.
                vote_record = {"uuid":uuid, "state":state, "session":year,
                      "state_bill_id":state_bill_id, "chamber":chamber, "date":vote_date,
                      "description":"", "yeas":final_votes["YEAS"], "nays":final_votes["NAYS"],
                      "other":final_votes["PRESENT"], "roll_call":roll_call}
                votes.append(vote_record)
                
            # Extract bill history
            bill_actions = extractHistory(status_url)
            if bill_actions:
                bill_record = {"uuid":uuid, "state":state, "session":year,
                      "state_bill_id":state_bill_id, "bill_history":bill_actions}
                bill_history.append(bill_record)
                
    with open(bill_metadata_json, 'w', encoding='utf-8') as f:
        json.dump(bill_metadata, f, ensure_ascii=False, indent=4)  
    
    with open(sponsors_json, 'w', encoding='utf-8') as f:
        json.dump(sponsors, f, ensure_ascii=False, indent=4)
        
    with open(votes_json, 'w', encoding='utf-8') as f:
        json.dump(votes, f, ensure_ascii=False, indent=4)  
        
    with open(bill_history_json, 'w', encoding='utf-8') as f:
        json.dump(bill_history, f, ensure_ascii=False, indent=4)  
