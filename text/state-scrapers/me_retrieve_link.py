from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.chrome.options import Options
from webdriver_manager.chrome import ChromeDriverManager
from lxml import html
import time
from bs4 import BeautifulSoup
import logging
# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# Set up headless Chrome
options = Options()
options.add_argument("--headless")
options.add_argument("--disable-gpu")
options.add_argument("--no-sandbox")
options.add_argument("--window-size=1920,1080")
options.add_argument("user-agent=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36")
service = Service(ChromeDriverManager().install())
driver = webdriver.Chrome(service=service, options=options)

def retrieve_bill_text(session, bill_number):
    logging.info(f"Retrieving bill text for {bill_number} in session {session}...")
    """
    Scrapes bill information from Maine Legislature website
    
    Args:
        bill_number (str): Bill number (e.g., 'HP1234')
        session (str): Session number (e.g., '126')
    
    Returns:
        dict: Dictionary containing scraped bill information
    """
    if session in ["125", "126"]:
        url = f"https://www.mainelegislature.org/legis/bills/display_ps.asp?paper={bill_number}&snum={session}"
    else:
        url = f"https://www.mainelegislature.org/legis/bills/display_ps.asp?snum={session}&ld={bill_number}"
    
    try:
        # Navigate to the URL
        driver.get(url)
        
        # Wait for page to load
        time.sleep(2)
        
        # Get page source and parse with lxml
        page_source = driver.page_source
        tree = html.fromstring(page_source)
        
        if session in ["120", "121", "122"]:
            html_elements = tree.xpath('//a[@class="html_btn"]/@href')
        else:
            html_elements = tree.xpath('//a[@class="small_html_btn"]/@href')
        
        billtext_urls = ["https://www.mainelegislature.org" + url for url in html_elements if 'billtexts' in url]

        return billtext_urls
        
    except Exception as e:
        logging.info(f"Error scraping bill {bill_number}: {str(e)}")
        return None
    
print("Starting to scrape Maine bill")
