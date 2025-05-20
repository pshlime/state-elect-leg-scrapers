from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.chrome.options import Options
from webdriver_manager.chrome import ChromeDriverManager
from lxml import html
import pandas as pd
import time

# Set up headless Chrome
options = Options()
options.add_argument("--headless")
options.add_argument("--disable-gpu")
options.add_argument("--no-sandbox")
options.add_argument("--window-size=1920,1080")
options.add_argument("user-agent=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36")

service = Service(ChromeDriverManager().install())
driver = webdriver.Chrome(service=service, options=options)

all_links = []

for year in range(2001, 2015):
    print(f"Scraping session {year}...")
    bills_url = f"https://www.capitol.hawaii.gov/sessions/session{year}/bills/"
    try:
        driver.get(bills_url)
        time.sleep(5)  # wait for Cloudflare or content to load

        tree = html.fromstring(driver.page_source)

        # Extract hrefs that end with .htm
        relative_links = tree.xpath('//a[substring(@href, string-length(@href) - 3) = ".htm"]/@href')
        bill_links = [f"https://www.capitol.hawaii.gov{href}" for href in relative_links]

        # Add session info
        for link in bill_links:
            all_links.append({"session": year, "bill_link": link})

    except Exception as e:
        print(f"Error scraping session {year}: {e}")
        continue

driver.quit()

# Save to CSV
df = pd.DataFrame(all_links)
df.to_csv("text/state-scrapers/hi_bill_links.csv", index=False)
print("Saved to text/state-scrapers/hi_bill_links.csv")
