import re
import requests
import json
from datetime import datetime
from bs4 import BeautifulSoup

# URL for the new HTML format example.
url = "https://www.leg.state.nv.us/Session/73rd2005/Reports/history.cfm?billname=SB478"  # Replace with actual URL

# Fetch the HTML from the website
response = requests.get(url)
response.raise_for_status()
html_content = response.text

# (Optional) Output the raw HTML for debugging
print("Raw HTML content:")
print(html_content)
print("="*80)

# Use html5lib to robustly parse the (possibly malformed) HTML.
soup = BeautifulSoup(html_content, 'html5lib')

# ------------------------------------------------------------------------------
# Extract basic bill information
# ------------------------------------------------------------------------------
# Try to extract the bill identifier from a large font element, e.g., <font size="6">, or fallback to the <title>
bill_id_tag = soup.find("font", {"size": "6"})
if bill_id_tag:
    state_bill_id = bill_id_tag.get_text(strip=True)
else:
    state_bill_id = soup.title.get_text(strip=True)

# For this example, the state is Nevada ("NV").
state = "NV"
# Generate a simple UUID by concatenating the state abbreviation with the bill ID.
uuid = state + state_bill_id

# Determine the legislative session.
# One approach: try to find a link that includes the session info.
session = ""
for a in soup.find_all("a", href=True):
    m = re.search(r'/Session/([^/]+)/bills/', a["href"])
    if m:
        session = m.group(1)
        break
# If not found, leave session empty (or set a default if desired).

# ------------------------------------------------------------------------------
# Extract bill history using the new table layout
# ------------------------------------------------------------------------------
bill_history = []

# Locate the table containing the "Bill History" header.
history_header = soup.find("strong", text="Bill History")
if history_header:
    history_table = history_header.find_parent("table")
    if history_table:
        # Get all table rows.
        trs = history_table.find_all("tr")
        # Iterate through table rows looking for ones that contain a JournalPopup link (which we assume to be the date row).
        for i, tr in enumerate(trs):
            a_tag = tr.find("a", href=True)
            if a_tag and "JournalPopup.cfm" in a_tag["href"]:
                # Extract the raw date string, e.g. "Mar 29, 2005"
                date_raw = a_tag.get_text(strip=True)
                try:
                    # Convert to YYYY-MM-DD format.
                    dt = datetime.strptime(date_raw, "%b %d, %Y")
                    date_formatted = dt.strftime("%Y-%m-%d")
                except Exception as e:
                    # If conversion fails, use the raw text.
                    date_formatted = date_raw

                # Look for the next row that contains the events (usually a <ul> in the <td>).
                if i + 1 < len(trs):
                    next_tr = trs[i + 1]
                    ul = next_tr.find("ul")
                    if ul:
                        li_tags = ul.find_all("li")
                        for li in li_tags:
                            # Extract the action text from the <li>.
                            action_text = li.get_text(" ", strip=True)
                            # Use simple heuristics to decide on a chamber prefix.
                            action_lower = action_text.lower()
                            if "assembly" in action_lower:
                                prefix = "A - "
                            elif "senate" in action_lower:
                                prefix = "S - "
                            else:
                                prefix = "H - "  # Default indicator if no keyword is found.
                            if not action_text.startswith(prefix):
                                action_text = prefix + action_text
                            bill_history.append({
                                "date": date_formatted,
                                "action": action_text
                            })

# ------------------------------------------------------------------------------
# Construct the final JSON object
# ------------------------------------------------------------------------------
result = {
    "uuid": uuid,
    "state": state,
    "session": session,           # Example: "73rd2005", if found from a link.
    "state_bill_id": state_bill_id,
    "bill_history": bill_history  # List of history event objects.
}

# Output the final JSON object.
print("JSON object:")
print(json.dumps(result, indent=4))
