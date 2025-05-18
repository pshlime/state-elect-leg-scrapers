import os
from pathlib import Path
import logging
from dotenv import load_dotenv
from google import genai
from concurrent.futures import ThreadPoolExecutor, as_completed
import pandas as pd
import re

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
load_dotenv()
GEMINI_APIKEY = os.getenv('GEMINI_APIKEY')
client = genai.Client(api_key=GEMINI_APIKEY)

PROMPT = """You will be provided with legislative text formatted in HTML. Your task is to process this HTML to isolate the core text while applying specific formatting for amendments.

Here are the rules:

1.  **Identify Inserted Language:**
    * Language originally marked with `<font color="BLUE">...</font>` (often representing new text, potentially also indicated by ALL CAPS in the source document, though the primary HTML marker is the blue font tag) must be wrapped with `<u class="amendmentInsertedText">` and `</u>`. For example, `<font color="BLUE">NEW TEXT</font>` should become `<u class="amendmentInsertedText">NEW TEXT</u>`.
    * Language that is to be inserted may also be marked with `<added>...</added>`, but the primary marker is the blue font tag. Again, the language should be wrapped with `<u class="amendmentInsertedText">` and `</u>`.

2.  **Identify Deleted Language:**
    * Language originally marked with `<font color="RED"><s>...</s></font>` (representing text to be removed) must be wrapped with `<strike class="amendmentDeletedText">` and `</strike>`. For example, `<font color="RED"><s>OLD TEXT</s></font>` should become `<strike class="amendmentDeletedText">OLD TEXT</strike>`.
    * Language that is to be deleted may also be marked with `<stricken>...</stricken>`. Again, the language should be wrapped with `<strike class="amendmentDeletedText">` and `</strike>`.
3.  **Remove General HTML Formatting but Preserve Structure:**
    * All other HTML tags (e.g., original `<u>` tags that are not part of the new classes, other `<font>` tags, `<b>`, `<i>`, `<span>`, etc.) should be removed, leaving only their inner text content.
    * Paragraph tags (`<p>` and `</p>`) should be handled to maintain paragraph separation (e.g., by ensuring newlines or appropriate spacing replace them). The goal is not to have `<p>` tags in the final output unless they are part of the content itself, but rather to preserve the visual separation they imply.

4.  **Convert HTML Entities:**
    * Common HTML entities (like `&nbsp;`) should be converted to their standard character equivalents (e.g., `&nbsp;` becomes a space).

5.  **Normalize Whitespace:**
    * After all transformations, ensure that any excess whitespace (e.g., multiple spaces, leading/trailing spaces on lines that shouldn't have them) is cleaned up to produce a neat and readable output.

The final output should be the processed text with only the specified `<u class="amendmentInsertedText">` and `<strike class="amendmentDeletedText">` tags for amendments, and all other HTML formatting removed.

Please note that there may be some variation in how the HTML formatting is indicated, but for the most part, all CAPS and blue should indicate insertions; things in red and any sort of strike out should indicate deletions.

Please process the HTML legislative text according to these rules. Please only return the text; do not include any additional explanations or comments. If for some  reason you cannot identify the relevant HTML tags for insertions and deletion, please return all of the legislative text cleaned up and without the HTML formatting."""

def scrape_text(file_path):
    """
    Scrape text file containing HTML formatting using Google Gemini API and save it as a .txt file.
    
    Args:
        file_path (str): The path to the text file.
    
    Returns:
        str: The extracted text from the HTML formatting.
    """
    logging.info(f"Uploading file: {file_path}")
    # Upload PDF
    raw_text = client.files.upload(file=file_path)
    logging.info("File uploaded successfully.")

    # Generate text using Gemini
    logging.info("Generating text using Gemini API...")
    response = client.models.generate_content(
        model="gemini-2.5-flash-preview-04-17",
        contents=[PROMPT, raw_text]
    )

    # Determine .txt file path
    logging.info("Generating text file...")
    txt_path = f"{os.path.splitext(file_path)[0]}_html.txt"

    # Write response to text file
    with open(txt_path, 'w', encoding='utf-8') as f:
        f.write(response.text)

    # Delete uploaded PDF file
    client.files.delete(name=raw_text.name)

    return response.text

def run_in_parallel(pdf_paths, max_workers=10):
    results = []
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        future_to_path = {executor.submit(scrape_text, path): path for path in pdf_paths}
        for future in as_completed(future_to_path):
            try:
                result = future.result()
                results.append(result)
            except Exception as e:
                path = future_to_path[future]
                logging.error(f"Unexpected failure: {path} - {e}")
                results.append({"pdf_path": path, "status": "failed", "error": str(e)})
    return results

# ------------------ MAIN ------------------

if __name__ == "__main__":
    df = pd.read_csv("AZ/output/az_bill_text_files.csv")

    text_dir = Path("/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/arizona")

    # Regex pattern to match files ending in '_html.txt'
    pattern = re.compile(r"_html\.txt$")

    # Collect the names of subfolders (i.e., UUIDs) containing at least one matching file
    existing_uuids = {
        f.parent.name
        for f in text_dir.rglob("*.txt")
        if pattern.search(f.name)
    }
   
    df = df[~df["UUID"].isin(existing_uuids)]

    file_path = df["file_path"].dropna().tolist()
    file_path = [p for p in file_path if os.path.exists(p)]

    logging.info(f"Starting parallel processing on {len(file_path)} files...")

    results = run_in_parallel(file_path, max_workers=6)

    logging.info("Processing completed.")