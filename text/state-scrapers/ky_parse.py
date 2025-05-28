import os
import logging
from dotenv import load_dotenv
from google import genai
from concurrent.futures import ThreadPoolExecutor, as_completed
import pandas as pd
from PyPDF2 import PdfReader, PdfWriter

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
load_dotenv()
GEMINI_APIKEY = os.getenv('GEMINI_APIKEY')
client = genai.Client(api_key=GEMINI_APIKEY)

PROMPT = """IMPORTANT: Output ONLY the text of the uploaded bill with the specified markup. DO NOT summarize, analyze, or add any commentary.

The uploaded PDF is a legislative bill. Your task is to process it as follows:

1. Identify any text with bold face and underlining (indicating insertion) and wrap it with: <u class="amendmentInsertedText"> and </u>

2. Identify any text surrounded with brackets (e.g, []) and with strikethrough (indicating deletion) and wrap it with: <strike class="amendmentDeletedText"> and </strike>

3. Remove any line numbers appearing in the original document.

4. Output the complete bill text with these markup tags in place.

If the bill contains no underlined or strikethrough text, simply output the plain text of the bill without any markup.

Do not include <br> tags in your output.

Your response must contain ONLY the processed bill text - no introduction, explanation, or commentary of any kind."""

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
    df = pd.read_csv("text/state-scrapers/ky_bill_text_files.csv")

    pdf_paths = df["file_path"].dropna().tolist()
    pdf_paths = [p for p in pdf_paths if os.path.exists(p)]

    logging.info(f"Starting parallel processing on {len(pdf_paths)} files...")

    results = run_in_parallel(pdf_paths, max_workers=4)