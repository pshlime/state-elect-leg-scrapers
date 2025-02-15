
import requests
from datetime import datetime
import re

import csv
import os

from lxml import html

BASE_URL = "https://docs.legis.wisconsin.gov/"

def scrape_bill(uuid, state, state_bill_id, session):
    metadata, link = scrape_bill_metadata(uuid, state, state_bill_id, session)
    append_to_csv(uuid, session, state_bill_id, link)

def scrape_bill_metadata(uuid, state, state_bill_id, session):
    bill_json_url = (
        "https://docs.legis.wisconsin.gov/{}/proposals/{}".format(session, state_bill_id)
    )

    response = requests.get(bill_json_url)
    tree = html.fromstring(response.content)

    bill_description = tree.xpath("//div[@class='box-content']/div/p//text()")
    bill_description_clean = bill_description[-1].strip().capitalize()

    history = tree.xpath("//div[@class='propHistory']/table[@class='history']/tr/td[@class='entry']//text()")
    last_status = history[-1]

    bill_metadata = {
        "uuid": uuid,
        "state": state,
        "session": session,
        "state_bill_id": state_bill_id,
        "title": 'NA',
        "description": bill_description_clean,
        "status": last_status,
        "state_url": bill_json_url,
    }

    links = tree.xpath("//div[@class='propLinks noprint']/ul/li/p/span/a")

    for link in links:
        text = link.xpath("./text()")[0]

        if text == "Bill Text":
            href = link.xpath("./@href")[0]
            url =  BASE_URL + href

    return bill_metadata, url

def scrape_bill_history(uuid, state, state_bill_id, session):
    bill_json_url = (
        "https://docs.legis.wisconsin.gov/{}/proposals/{}".format(session, state_bill_id)
    )

    response = requests.get(bill_json_url)
    tree = html.fromstring(response.content)

    history = tree.xpath("//div[@class='propHistory']/table[@class='history']/tr")

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

    print(bill_history_data)

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

    scrape_bill_history(test_uuid, test_state, test_bill_id, test_session)
