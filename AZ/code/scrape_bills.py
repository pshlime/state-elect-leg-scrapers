import json
import requests
import datetime
import re

from lxml import html

def scrape_bill(uuid, state, state_bill_id, session):
    bill_history_data, last_status, action_ids = scrape_bill_history(uuid, state, state_bill_id, session)
    write_file(uuid, "bill_history", bill_history_data)

    bill_meta_data, internal_id = scrape_bill_metadata(uuid, state, state_bill_id, session, last_status)
    write_file(uuid, "bill_metadata", bill_meta_data)

    sponsors_data = scrape_sponsors(uuid, state, state_bill_id, session, internal_id)
    write_file(uuid, "sponsors", sponsors_data)

    for voting in scrape_votes(uuid, state, state_bill_id, session, internal_id, action_ids):
        voting_data, date = voting

        file_name = "{}_{}".format(uuid, date)
        write_file(file_name, "votes", voting_data)

def scrape_bill_metadata(uuid, state, state_bill_id, session, last_status):
    session_id = get_session_id(session)
    bill_json_url = (
        "https://apps.azleg.gov/api/Bill/?billNumber={}&sessionId={}".format(state_bill_id, session_id)
    )

    page = json.loads(requests.get(bill_json_url, timeout=80).content.decode("utf-8"))

    bill_title = page["ShortTitle"]
    internal_id = page["BillId"]
    bill_description = page["Description"]
    bill_url = (
        "https://apps.azleg.gov/BillStatus/BillOverview/{}?SessionId={}".format(
            internal_id, session_id
        )
    )

    bill_metadata = {
        "uuid": uuid,
        "state": state,
        "session": session,
        "state_bill_id": state_bill_id,
        "title": bill_title,
        "description": bill_description,
        "status": last_status,
        "state_url": bill_url,
    }

    return bill_metadata, internal_id

def scrape_sponsors(uuid, state, state_bill_id, session, internal_id):
    sponsors_url = "https://apps.azleg.gov/api/BillSponsor/?id={}".format(
        internal_id
    )
    page = json.loads(requests.get(sponsors_url, timeout=80).content.decode("utf-8"))


    sponsors = []
    for sponsor in page:
        if "Prime" in sponsor["SponsorType"]:
            sponsor_type = "sponsor"
        else:
            sponsor_type = "cosponsor"

        sponsor_name = sponsor["Legislator"]["MemberShortName"]

        sponsors.append({
            "sponsor_name": sponsor_name,
            "sponsor_type": sponsor_type,
        })

    sponsor_data = {
        "uuid": uuid,
        "state": state,
        "session": session,
        "state_bill_id": state_bill_id,
        "sponsors": sponsors
    }

    return sponsor_data

def scrape_bill_history(uuid, state, state_bill_id, session):
    session_id = get_session_id(session)
    bill_json_url = (
        "https://apps.azleg.gov/api/BillStatusOverview/?billNumber={}&sessionId={}".format(state_bill_id, session_id)
    )
    response = requests.get(bill_json_url, timeout=80)
    page = json.loads(response.content.decode("utf-8"))

    actions = []
    actions_ids = []

    body_types = {
        "H": "House",
        "S": "Senate"
    }
    action_types = {
        "FINAL": "Final Passage",
        "THIRD": "Third Reading",
        "SECOND": "Second Reading",
        "FIRST": "First Reading"
    }

    for status in page:
        action_type = status["DateType"]
        action_body = status["Body"]
        action_id = status["BillStatusActionId"]

        if action_body in body_types:
            action_body = body_types[action_body]

        if action_type in action_types:
            action_type = action_types[action_type]

        action = (
            "{}: {}".format(action_body, action_type)
        )

        date = status["SortedDate"]
        date_formatted = date.split("T")[0]

        action_data = {
            "date": date_formatted,
            "action": action,
        }

        actions.append(action_data)
        actions_ids.append(action_id)

    bill_history_data = {
        "uuid": uuid,
        "state": state,
        "session": session,
        "state_bill_id": state_bill_id,
        "history": actions
    }

    return bill_history_data, actions[-1]["action"], actions_ids

def scrape_votes(uuid, state, state_bill_id, session, internal_id, action_ids):
    response_key = {
        "Y": "Yea",
        "N": "Nay",
        "AB": "Absent",
        "NV": "Not Voting",
    }

    for action_id in action_ids:
        action_url = (
            "https://apps.azleg.gov/api/BillStatusFloorAction/?billStatusId={}&billStatusActionId={}&includeVotes=true".format(internal_id, action_id)
        )
        response = requests.get(action_url, timeout=80)
        page = json.loads(response.content.decode("utf-8"))

        if page:
            floor_action = page[0]
            votes = floor_action["Votes"]

            if votes:
                description = floor_action["CommitteeName"]
                chamber = votes[0]["Legislator"]["Body"]
                report_date = floor_action["ReportDate"].split("T")[0]
                ayes = floor_action["Ayes"]
                nays = floor_action["Nays"]
                other = floor_action["Absent"] + floor_action["NotVoting"] + floor_action["Present"] + floor_action["Excused"] + floor_action["Vacant"]

                roll_call = []

                for vote in votes:
                    try:
                        response = response_key[vote["Vote"]]
                        voter_name = vote["Legislator"]["MemberShortName"]

                        indv_roll_call = {
                            "name": voter_name,
                            "response": response,
                        }

                        roll_call.append(indv_roll_call)
                    except KeyError:
                        raise KeyError('unexpected response')

                votes_data = {
                    "uuid": uuid,
                    "state": state,
                    "session": session,
                    "state_bill_id": state_bill_id,
                    "chamber": chamber,
                    "date": report_date,
                    "description": description,
                    "yeas": ayes,
                    "nays": nays,
                    "other": other,
                    "roll_call": roll_call
                }

                date_without_dash = re.sub("-", "", report_date)

                yield votes_data, date_without_dash
            else:
                continue
        else:
            continue


def get_session_id(session_name):
    with open('./arizona_session_ids.json', 'r') as file:
        data = json.load(file)

    for session in data:
        if session["Name"] == session_name:
            return session["SessionId"]

    raise KeyError("Cannot find session")

def write_file(file_name, directory, data):
    with open(f'../output/{directory}/{file_name}.json', 'w') as f:
        json.dump(data, f, indent=4)

if __name__ == "__main__":
    test_uuid = "AZ1995H2020"
    test_state = "AZ"
    test_bill_id = "HB2020"
    test_session = "1995 - Forty-second Legislature - First Regular Session"

    scrape_bill(test_uuid, test_state, test_bill_id, test_session)
