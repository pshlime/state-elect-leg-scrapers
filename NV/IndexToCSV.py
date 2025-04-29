import csv
import requests
from bs4 import BeautifulSoup

# List of websites to process.
# Each dictionary should include the URL to process and a nickname for the CSV output.
websites = [
    {
        "url": "https://www.leg.state.nv.us/Session/70th1999/Reports/BillIndex.html",
        "nickname": "70th"
    },
    {
       "url": "https://www.leg.state.nv.us/Session/71st2001/Reports/BillIndex.htm",
         "nickname": "71st"
    },
    {
       "url": "https://www.leg.state.nv.us/Session/72nd2003/Reports/TablesAndIndex/BillIndex.html",
         "nickname": "72st"
    },
    {
       "url": "https://www.leg.state.nv.us/Session/73rd2005/Reports/TablesAndIndex/index.html",
         "nickname": "73st"
    },
    {
       "url": "https://www.leg.state.nv.us/Session/74th2007/Reports/TablesAndIndex/index.html",
         "nickname": "74st"
    },
]

# Process each website in the list.
for site in websites:
    bill_data = {}  # Reset data for each site.
    url = site["url"]
    filenickname = site["nickname"]

    # Retrieve the HTML from the website.
    response = requests.get(url)
    response.raise_for_status()  # Raise an exception if there is any problem with the fetch.

    soup = BeautifulSoup(response.text, "html.parser")

    processing = False

    # Process each <p> tag.
    for p_tag in soup.find_all("p"):
        # Check for the starting marker if not already processing.
        if not processing:
            if p_tag.get("class") and "Level0" in p_tag.get("class"):
                # Start processing if we find the starting marker.
                if p_tag.find("a", attrs={"name": "BIELECTIONS"}):
                    processing = True
            continue

        # Stop processing when hitting the next Level0 <p> that is not our marker.
        if p_tag.get("class") and "Level0" in p_tag.get("class"):
            if not p_tag.find("a", attrs={"name": "BIELECTIONS"}):
                break

        # Extract text that appears before the first <a> tag.
        preceding_text = ""
        for content in p_tag.contents:
            if getattr(content, "name", None) == "a":
                break
            if isinstance(content, str):
                preceding_text += content.strip()
        preceding_text = preceding_text.rstrip(',').replace('\n', ' ')

        # Process all <a> tags within this <p> tag.
        for a_tag in p_tag.find_all("a"):
            link = a_tag.get("href")
            bill_name = a_tag.get_text(strip=True).replace(' ', "").replace('\n', "")
            full_link = "https://www.leg.state.nv.us/" + link.lstrip('/')

            if bill_name in bill_data:
                existing_link, existing_text = bill_data[bill_name]
                if preceding_text and preceding_text not in existing_text:
                    aggregated_text = existing_text + "; " + preceding_text
                    bill_data[bill_name] = (existing_link, aggregated_text)
            else:
                bill_data[bill_name] = (full_link, preceding_text)

    # Write the result to a CSV file.
    csv_filename = f'bills_{filenickname}.csv'
    with open(csv_filename, 'w', newline='', encoding='utf-8') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(["Bill Name", "Link", "All Preceding Texts"])
        for bill, (link, text) in bill_data.items():
            writer.writerow([bill, link, text])

    print(f"CSV file '{csv_filename}' has been created for {url}.")
