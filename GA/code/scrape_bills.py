from suds.client import Client
import logging
import socket
import urllib.error
import time
import suds
import requests
from hashlib import sha512
import pandas as pd
import json
import re
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed
import os

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

SESSION_SITE_IDS = {
    "2023_24": 1031,
    "2021_ss": 1030,
    "2021_22": 1029,
    "2020_ss": "1027",
    "2019_20": 27,
    "2018_ss": 26,
    "2017_18": 25,
    "2015_16": 24,
    "2013_14": 23,
    "2011_ss": 22,
    "2011_12": 21,
    "2009_10": 20,
    "2007_08": 18,
    "2005_06": 14,
    "2003_04": 11,
    "2001_02": 1,
}

action_code_map = {
    "HI": None,
    "SI": None,
    "HH": ["introduction"],
    "SH": ["introduction"],
    "HPF": ["filing"],
    "HDSAS": None,
    "SPF": ["filing"],
    "HSR": ["reading-2"],
    "SSR": ["reading-2"],
    "HFR": ["reading-1"],
    "SFR": ["reading-1"],
    "HRECM": ["withdrawal", "referral-committee"],
    "SRECM": ["withdrawal", "referral-committee"],
    "SW&C": ["withdrawal", "referral-committee"],
    "HW&C": ["withdrawal", "referral-committee"],
    "HRA": ["passage"],
    "SRA": ["passage"],
    "HPA": ["passage"],
    "HRECO": None,
    "SPA": ["passage"],
    "HTABL": None,  # 'House Tabled' - what is this?
    "SDHAS": None,
    "HCFR": ["committee-passage-favorable"],
    "SCFR": ["committee-passage-favorable"],
    "HRAR": ["referral-committee"],
    "SRAR": ["referral-committee"],
    "STR": ["reading-3"],
    "SAHAS": None,
    "SE": ["passage"],
    "SR": ["referral-committee"],
    "HTRL": ["reading-3", "failure"],
    "HTR": ["reading-3"],
    "S3RLT": ["reading-3", "failure"],
    "HASAS": None,
    "S3RPP": None,
    "STAB": None,
    "SRECO": None,
    "SAPPT": None,
    "HCA": None,
    "HNOM": None,
    "HTT": None,
    "STT": None,
    "SRECP": None,
    "SCRA": None,
    "SNOM": None,
    "HRECL": None,
    "SPFR": None,
    "S2R": ["reading-2"],
    "H2R": ["reading-2"],
    "SENG": ["passage"],
    "HENG": ["passage"],
    "HPOST": None,
    "HCAP": None,
    "SDSG": ["executive-signature"],
    "SSG": ["executive-receipt"],
    "Signed Gov": ["executive-signature"],
    "HDSG": ["executive-signature"],
    "HSG": ["executive-receipt"],
    "EFF": None,
    "HRP": None,
    "STH": None,
    "HTS": None,
}

vote_name_pattern = re.compile(r"(.*), (\d+(?:ST|ND|RD|TH))", re.IGNORECASE)

url = "http://webservices.legis.ga.gov/GGAServices/%s/Service.svc?wsdl"


def get_client(service):
    client = backoff(Client, get_url(service), autoblend=True)
    return client


def get_url(service):
    return url % (service)


def backoff(function, *args, **kwargs):
    retries = 5

    def _():
        time.sleep(1)  # Seems like their server can't handle the load.
        return function(*args, **kwargs)

    for attempt in range(retries):
        try:
            return _()
        except (socket.timeout, urllib.error.URLError, suds.WebFault) as e:
            if "This Roll Call Vote is not published." in str(e):
                raise ValueError("Roll Call Vote isn't published")

            backoff = (attempt + 1) * 15
            logging.warning(
                "[attempt %s]: Connection broke. Backing off for %s seconds."
                % (attempt, backoff)
            )
            logging.info(str(e))
            time.sleep(backoff)

    raise ValueError("The server's not playing nice. We can't keep slamming it.")


def get_key(timestamp):
    # this comes out of Georgia's javascript
    # 1) part1 (and the overall format) comes from
    #   (e.prototype.getKey = function (e, t) {
    #     return Ht.SHA512("QFpCwKfd7f" + c.a.obscureKey + e + t);
    #
    # 2) part2 is obscureKey in the source code :)
    #
    # 3) e is the string "letvarconst"
    # (e.prototype.refreshToken = function () {
    #   return this.http
    #     .get(c.a.apiUrl + "authentication/token", {
    #       params: new v.f()
    #         .append("key", this.getKey("letvarconst", e))
    part1 = "QFpCwKfd7"
    part2 = "fjVEXFFwSu36BwwcP83xYgxLAhLYmKk"
    part3 = "letvarconst"
    key = part1 + part2 + part3 + timestamp
    return sha512(key.encode()).hexdigest()


def get_token():
    timestamp = str(int(time.time() * 1000))
    key = get_key(timestamp)
    token_url = (
        f"https://www.legis.ga.gov/api/authentication/token?key={key}&ms={timestamp}"
    )
    return "Bearer " + requests.get(token_url).json()

def write_file(file_name, directory, data):
    with open(f'GA/output/{directory}/{file_name}.json', 'w') as f:
        json.dump(data, f, indent=4)

def get_bill_metadata(uuid, session, instrument):
    """
    Get bill metadata from the instrument object.
    """
    logging.info(f"Getting bill metadata for {uuid} ({session})")
    metadata = {
        "uuid": uuid,
        "state": "GA",
        "session": session,
        "state_bill_id": f"{instrument.DocumentType} {instrument.Number}",
        "title": instrument.Caption,
        "description": instrument.Caption,
        "status": instrument.Status['Description'],
        "state_url": f"https://www.legis.ga.gov/legislation/{instrument.Id}",
    }

    return metadata

def get_bill_sponsors(uuid, session, authors, instrument):
    """
    Get bill sponsors from the instrument object.
    """
    logging.info(f"Getting bill sponsors for {uuid} ({session})")
    sponsors = []
    for sponsor in authors[0]:
        sponsor_name =sponsor["MemberDescription"]
        sponsor_name = re.sub(r'\s\d+(st|nd|rd|th)$', '', sponsor_name)
        sponsor_position = sponsor["Sequence"]
        if sponsor_position == 1:
            sponsor_type = "sponsor"
        else:
            sponsor_type = "cosponsor"

        sponsors.append({
            "sponsor_name": sponsor_name,
            "sponsor_type": sponsor_type
        })

    sponsor_data = {
            "uuid": uuid,
            "state": "GA",
            "session": session,
            "state_bill_id": f"{instrument.DocumentType} {instrument.Number}",
            "sponsors": [sponsors]
        }
    return sponsor_data

def get_bill_history(uuid, session, status_history, instrument):
    """
    Get bill history from the instrument object and save it to a CSV file.
    """
    logging.info(f"Getting bill history for {uuid} ({session})")
    history = []
    for status in status_history:
        date = status["Date"].date().strftime("%Y-%m-%d")
        action = f"{action_code_map[status["Code"]]} - {status["Description"]}"

        history.append({
            "date": date,
            "action": action  
        })

    history_data = {
            "uuid": uuid,
            "state": "GA",
            "session": session,
            "state_bill_id": f"{instrument.DocumentType} {instrument.Number}",
            "history": [history]
        }
    return history_data

def get_votes(uuid, session, votes, instrument, vservice):
    """
    Get votes from the instrument object.
    """
    logging.info(f"Getting votes for {uuid} ({session})")
    for vote in votes:
        vote_details = backoff(vservice.GetVote, vote["VoteId"])
    
        roll_call = vote_details.Votes["MemberVote"]
        roll_call_records = []
        for r in roll_call:
            member = r['Member']['Name']

            vote_name_pattern = re.compile(r"(.*), (\d+(?:ST|ND|RD|TH))", re.IGNORECASE)
            match = vote_name_pattern.search(member)
            if member == 'VACANT':
                logging.warning(f"No match for member string: {member}. Skipping.")
                continue
            else:
                name, district = match.groups()

            response = r['MemberVoted']
            response = "NV" if response == "NotVoting" else str(r['MemberVoted'])

            roll_call_records.append({
                "name": name,
                "response": response
            })

        votes_data = {
            "uuid": uuid,
            "state": "GA",
            "session": session,
            "state_bill_id": f"{instrument.DocumentType} {instrument.Number}",
            "chamber": "H" if vote_details.Branch == "House" else "S",
            "date": vote_details.Date.date().strftime("%Y-%m-%d"),
            "description": f"{vote_details.Caption}-{vote_details.Description}",
            "yeas": vote_details.Yeas,
            "nays": vote_details.Nays,
            "other": vote_details.Excused + vote_details.NotVoting,
            "roll_call": [roll_call_records]
        }

        file_name = f"{uuid}_{vote_details.VoteId}"
        write_file(file_name, "votes", votes_data)


def get_bill_text_link(uuid, versions):
    """
    Get bill text link from the instrument object.
    Returns a 1-row DataFrame with uuid, text_url, and text_version.
    """
    logging.info(f"Getting bill text link for {uuid}")
    links = pd.DataFrame(columns=['uuid', 'text_url', 'text_version'])
    for version in versions:
        text_url = version['Url']
        text_version = version['Version']

        # Create 1-row DataFrame
        version_text = pd.DataFrame([{
            'uuid': uuid,
            'text_url': text_url,
            'text_version': text_version
        }])

        links = pd.concat([links, version_text], ignore_index=True)

    # In case versions is empty
    return links

def process_session(s, bill_list):
    session_bills = bill_list[bill_list["session"] == s]
    sid = SESSION_SITE_IDS[s]
    lservice = get_client("Legislation").service
    vservice = get_client("Votes").service

    text_links_local = []

    for index, row in session_bills.iterrows():
        UUID = row["UUID"]
        api_id = row["ga_id"]
        logging.info(f"[{s}] Processing bill {UUID} ({api_id})")

        instrument = backoff(lservice.GetLegislationDetail, api_id)

        bill_metadata = get_bill_metadata(UUID, s, instrument)
        write_file(UUID, "bill_metadata", bill_metadata)

        sponsors = get_bill_sponsors(UUID, s, instrument.Authors, instrument)
        write_file(UUID, "sponsors", sponsors)

        bill_history = get_bill_history(UUID, s, instrument.StatusHistory['StatusListing'], instrument)
        write_file(UUID, "bill_history", bill_history)

        if instrument.Votes is not None and 'VoteListing' in instrument.Votes:
            votes = instrument.Votes['VoteListing']
            get_votes(UUID, s, votes, instrument, vservice)

        text_link_df = get_bill_text_link(UUID, instrument.Versions['DocumentDescription'])
        text_links_local.append(text_link_df)

    return pd.concat(text_links_local, ignore_index=True)

# === Main Execution ===
if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")

    bill_list = pd.read_csv("GA/output/ga_legislation_by_session_merged.csv")
    metadata_dir = "GA/output/bill_metadata"
    existing_uuids = {filename.removesuffix(".json") for filename in os.listdir(metadata_dir)}

    bill_list = bill_list[~bill_list["UUID"].isin(existing_uuids)]
    sessions = ['2001_02', '2003_04', '2005_06', '2007_08', '2009_10', '2011_12', '2013_14']

    all_text_links = []

    with ThreadPoolExecutor(max_workers=7) as executor:
        future_to_session = {executor.submit(process_session, s, bill_list): s for s in sessions}

        for future in as_completed(future_to_session):
            s = future_to_session[future]
            try:
                text_links_df = future.result()
                all_text_links.append(text_links_df)
            except Exception as exc:
                logging.error(f"{s} generated an exception: {exc}")

    final_text_links = pd.concat(all_text_links, ignore_index=True)
    final_text_links.to_csv("GA/output/ga_bill_text_links.csv", index=False)