
import requests
from datetime import datetime
import re

import csv
import os

from lxml import html

BASE_URL = "https://docs.legis.wisconsin.gov/"

motion_classifiers = {
    "(Assembly|Senate)( substitute)? amendment": "amendment",
    "Report (passage|concurrence)": "passage",
    "Report (adoption|introduction and adoption) of Senate( Substitute)? Amendment": "amendment",
    "Report Assembly( Substitute)? Amendment": "amendment",
    "Read a third time": "passage",
    "Adopted": "passage",
}

def scrape_bill(uuid, state, state_bill_id, session):
    bill_url = (
        "https://docs.legis.wisconsin.gov/{}/proposals/{}".format(session, state_bill_id)
    )
    response = requests.get(bill_url)
    tree = html.fromstring(response.content)

    metadata, link = scrape_bill_metadata(uuid, state, state_bill_id, session, tree, bill_url)
    #append_to_csv(uuid, session, state_bill_id, link)
    scrape_bill_sponsors(uuid, state, state_bill_id, session, tree)

def scrape_bill_metadata(uuid, state, state_bill_id, session, page, page_url):
    bill_description = page.xpath("//div[@class='box-content']/div/p//text()")
    bill_description_clean = bill_description[-1].strip().capitalize()

    history = page.xpath("//div[@class='propHistory']/table[@class='history']/tr/td[@class='entry']//text()")
    last_status = history[-1]

    bill_metadata = {
        "uuid": uuid,
        "state": state,
        "session": session,
        "state_bill_id": state_bill_id,
        "title": 'NA',
        "description": bill_description_clean,
        "status": last_status,
        "state_url": page_url,
    }

    links = page.xpath("//div[@class='propLinks noprint']/ul/li/p/span/a")

    for link in links:
        text = link.xpath("./text()")[0]

        if text == "Bill Text":
            href = link.xpath("./@href")[0]
            url =  BASE_URL + href

    return bill_metadata, url

def scrape_bill_sponsors(uuid, state, state_bill_id, session, page):
    sponsors = page.xpath("//div[@class='propHistory']/table[@class='history']/tr/td[@class='entry']//text()")[0]

    if ";" in sponsors:
        lines = sponsors.split(";")
    else:
        lines = [sponsors]

    sponsor_list = []
    for line in lines:
        match = re.match(
                    "(Introduced|cosponsored|Cosponsored) by (?:joint )?(Senator|Representative|committee|Joint Legislative Council|Law Revision Committee)s?(.*)",
                    line.strip(),
                )

        type, _, people = match.groups()

        if type == "Introduced":
            sponsor_type = "sponsor"
        elif type == "Cosponsored" or type == "cosponsored":
            sponsor_type = "cosponsor"

        for r in re.split(r"\sand\s|\,", people):
            if r.strip():
                sponsor_list.append({
                    "sponsor_name": r.strip().rstrip('.'),
                    "sponsor_type": sponsor_type,
                })

    sponsor_data = {
        "uuid": uuid,
        "state": state,
        "session": session,
        "state_bill_id": state_bill_id,
        "sponsors": sponsor_list
    }

    return sponsor_data

def scrape_bill_history(uuid, state, state_bill_id, session, page):
    # bill_json_url = (
    #     "https://docs.legis.wisconsin.gov/{}/proposals/{}".format(session, state_bill_id)
    # )

    # response = requests.get(bill_json_url)
    # tree = html.fromstring(response.content)

    history = page.xpath("//div[@class='propHistory']/table[@class='history']/tr")

    actions = []
    for event in history:
        date = event.xpath("./td[@class='date']/text()")[0].strip()
        date_object = datetime.strptime(date, "%m/%d/%Y")
        formatted_date = date_object.strftime("%Y-%m-%d")

        house = event.xpath("./td[@class='date']/abbr/text()")[0]

        event_description = "".join(event.xpath("./td[@class='entry']//text()"))
        event_description_clean = house + " - " + event_description

        action_data = {
            "date": formatted_date,
            "action": event_description_clean,
        }

        actions.append(action_data)

    bill_history_data = {
        "uuid": uuid,
        "state": state,
        "session": session,
        "state_bill_id": state_bill_id,
        "history": actions
    }

    return bill_history_data

def append_to_csv(uuid, session, bill_number, link):
    filename = "bills.csv"
    file_exists = os.path.isfile(filename)

    with open(filename, mode="a", newline="") as file:
        writer = csv.writer(file)

        if not file_exists:
            writer.writerow(["uuid", "session", "bill_number", "link"])

        writer.writerow([uuid, session, bill_number, link])


if __name__ == "__main__":
    test_uuid = "WI1995AB694"
    test_state = "WI"
    test_bill_id = "SB125"
    test_session = "1995"

    scrape_bill(test_uuid, test_state, test_bill_id, test_session)
