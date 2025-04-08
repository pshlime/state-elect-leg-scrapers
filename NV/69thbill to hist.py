import re
import requests
import json
from datetime import datetime
from bs4 import BeautifulSoup

# URL to scrape
url = "https://www.leg.state.nv.us/Session/69th1997/tracking/Detail.cfm?dbo_in_intro__introID=699"

# Fetch the HTML from the website
response = requests.get(url)
response.raise_for_status()  # Ensure a successful response

# Output the raw HTML for reference
html_content = response.text
print("Raw HTML content:")
print(html_content)
print("="*80)  # Separator

# Parse the HTML using html5lib to better handle unclosed tags.
soup = BeautifulSoup(html_content, 'html5lib')

# ------------------------------------------------------------------------------
# Extract basic bill information
# ------------------------------------------------------------------------------
# Get the bill identifier from the <h1> tag (if available) or fallback to the <title>
bill_id_tag = soup.find('h1')
if bill_id_tag:
    state_bill_id = bill_id_tag.get_text(strip=True)
else:
    state_bill_id = soup.title.get_text(strip=True)





# Hardcode the state as Nevada (NV)
state = "NV"


# Extract the legislative session from the URL.
session_match = re.search(r'/Session/([^/]+)/', url)
if session_match:
    session = session_match.group(1)
else:
    session = ""
# Create a placeholder UUID.
uuid = state + session+ state_bill_id 
# ------------------------------------------------------------------------------
# Extract bill history from the <ul> of <li> events
# ------------------------------------------------------------------------------
bill_history = []

# Find the <ul> that holds the bill events.
ul = soup.find('ul')
if ul:
    # Using html5lib should result in each <li> being correctly recognized.
    li_tags = ul.find_all('li')
    
    for li in li_tags:
        # Get the text from each <li> and normalize whitespace
        text = li.get_text(" ", strip=True)
        # Expect the event text to start with a date (mm/dd/yy).
        # Split the text into date and action description.
        parts = text.split(maxsplit=1)
        if len(parts) < 2:
            continue  # Skip if the text is malformed.
        
        date_str, action_text = parts[0], parts[1]
        # Convert the date to the YYYY-MM-DD format.
        try:
            dt = datetime.strptime(date_str, "%m/%d/%y")
            date_formatted = dt.strftime("%Y-%m-%d")
        except ValueError:
            date_formatted = date_str  # Fall back if the date can't be parsed.
        
        # Determine a chamber indicator using simple heuristics.
        action_lower = action_text.lower()
        if "assembly" in action_lower:
            prefix = "A - "
        elif "senate" in action_lower:
            prefix = "S - "
        elif "house" in action_lower:
            prefix = "H - "
        else:
            prefix = "Null - "  # Default indicator if nothing matches.
        
        # Prepend the prefix if it isn't already present.
        if not action_text.startswith(prefix):
            action_text = prefix + action_text

        bill_history.append({
            "date": date_formatted,
            "action": action_text
        })

# ------------------------------------------------------------------------------
# Construct the final JSON object with the required fields
# ------------------------------------------------------------------------------
result = {
    "uuid": uuid,
    "state": state,
    "session": session,
    "state_bill_id": state_bill_id,
    "bill_history": bill_history
}

# Output the final JSON object
print("JSON object:")
print(json.dumps(result, indent=4))
