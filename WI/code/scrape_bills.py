
import requests
import datetime
import re

from lxml import html

BASE_URL = "https://docs.legis.wisconsin.gov/"

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

if __name__ == "__main__":
    test_uuid = "test"
    test_state = "WI"
    test_bill_id = "SB125"
    test_session = "1995"

    scrape_bill_metadata(test_uuid, test_state, test_bill_id, test_session)
