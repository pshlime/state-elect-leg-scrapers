import os
import logging
from dotenv import load_dotenv
from google import genai
from concurrent.futures import ThreadPoolExecutor, as_completed
import pandas as pd
from PyPDF2 import PdfReader, PdfWriter
import re
from pathlib import Path

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
load_dotenv()
GEMINI_APIKEY = os.getenv('GEMINI_APIKEY')
client = genai.Client(api_key=GEMINI_APIKEY)

PROMPT = """IMPORTANT: Output ONLY the processed bill text with the specified markup. DO NOT summarize, analyze, or add any commentary.
    The uploaded PDF is a Maryland legislative bill. Your task is to process it to show final policy changes:
    1. REMOVE the explanation block at the top that begins with "EXPLANATION: CAPITALS INDICATE MATTER ADDED TO EXISTING LAW"

    2. REMOVE all line numbers that appear in the left margin.

    3. REMOVE administrative boilerplate including:
    - File codes, bill status indicators, committee references
    - Proofreader lines, Governor presentation text, blanks and underscores
    - Any barcodes or identifier codes

    4. Apply policy change markup:
    - Text indicating NEW POLICY (BOLD CAPS, underlined additions) → wrap with: <u class="amendmentInsertedText"> and </u>
    - Text indicating REMOVED POLICY ([brackets], strikethrough deletions) → wrap with: <strike class="amendmentDeletedText"> and </strike>

    5. PRESERVE all substantive content including:
    - Bill title and purpose
    - All legislative text and structure
    - Section headings and legal language

    The goal is to clearly show what policy language is being added versus what is being removed from existing law.

    Processing priority: Focus on the final policy outcome - what will be new law versus what current law is being eliminated.

    Output the complete processed bill text with markup tags in place.

    Your response must contain ONLY the processed bill text - no introduction, explanation, or commentary of any kind.

    Process ONLY the exact text visible in the document. Do not add, complete, or infer any content not explicitly shown.
    """

def scrape_text(pdf_path):
    """
    Scrape text from a PDF file using Google Gemini API and save it as a .txt file.
    
    Args:
        pdf_path (str): The path to the PDF file.
    
    Returns:
        str: The extracted text from the PDF.
    """

    reader = PdfReader(pdf_path)
    total_pages = len(reader.pages)

    if total_pages > 80:
        logging.info(f"Skipping {pdf_path}: too long ({total_pages} pages)")
        return None
    
    logging.info(f"Uploading PDF file: {pdf_path}")
    # Upload PDF
    raw_text = client.files.upload(file=pdf_path)
    logging.info("PDF file uploaded successfully.")

    # Generate text using Gemini
    logging.info("Generating text using Gemini API...")
    response = client.models.generate_content(
        model="gemini-2.5-flash-preview-04-17",
        contents=[PROMPT, raw_text]
    )

    # Determine .txt file path
    logging.info("Generating text file...")
    txt_path = f"{os.path.splitext(pdf_path)[0]}_html.txt"

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
    df = pd.read_csv("text/state-scrapers/md_bill_text_files.csv")

    text_dir = Path("/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/maryland")
    # Regex pattern to remove '_<number>_html.txt' at the end
    existing_uuids = {
        f.parent.name for f in text_dir.rglob("*_html.txt")
    }
   
    df = df[~df["UUID"].isin(existing_uuids)]

    pdf_paths = df["file_path"].dropna().tolist()
    pdf_paths = [p for p in pdf_paths if os.path.exists(p)]

    logging.info(f"Starting parallel processing on {len(pdf_paths)} files...")

    results = run_in_parallel(pdf_paths, max_workers=5)
