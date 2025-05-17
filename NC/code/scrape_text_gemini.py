import os
import logging
from dotenv import load_dotenv
from google import genai
from concurrent.futures import ThreadPoolExecutor, as_completed
import pandas as pd

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
load_dotenv()
GEMINI_APIKEY = os.getenv('GEMINI_APIKEY')
client = genai.Client(api_key=GEMINI_APIKEY)

PROMPT = """Please parse the text content of the provided legislative bill (PDF file).

Your task is to process the text according to the following instructions:

1.  **Identify Amendments:** Recognize text that was originally marked as inserted (typically by underlining) and text that was originally marked as deleted (typically by a strikethrough).
2.  **Apply Specific Tags Precisely:**
    * For all underlined text, enclose it precisely with the tags `<u class="amendmentInsertedText">` and `</u>`.
    * For all text that has a strikethrough, enclose it precisely with the tags `<strike class="amendmentDeletedText">` and `</strike>`.
    * **Contiguous Formatting:** Group contiguous words, numbers, punctuation marks, or sequences of characters that share the *exact same* original formatting (all underlined or all strikethrough) under a single corresponding tag. Do not create separate tags for each word within a continuously underlined or strikethrough phrase.
    * **Interleaved Formatting:** Apply separate tags for interleaved text with different formatting (e.g., deleted text adjacent to inserted text, or blocks of formatted text separated by unformatted text).
3.  **Handle Replacements:** In cases where deleted text is immediately followed by inserted text (indicating a replacement of old language with new), apply the tags in sequence: `<strike class="amendmentDeletedText">Deleted Text</strike> <u class="amendmentInsertedText">Inserted Text</u>`. Ensure the "Contiguous Formatting" rule is applied when determining the content within the `<strike>` and `<u>` tags in replacements.
4.  **Catch stand-alone underlined and strikethrough text:** If there are instances of inserted (underlined) or deleted (strikethrough) text that do not immediately have replacements, be sure to still apply the appropriate tags according to the rules above.
5.  **Preserve Structure and Content:** Maintain the original paragraph breaks, line breaks, and the overall flow and structure of the document as closely as possible. Include all substantive text and sections from the document.
6.  **Remove Extraneous Lines:** Filter out and do NOT include lines that contain only non-content markers such as:
    * Page numbers (e.g., "Page 1", "Page 2")
    * Repeating headers or footers that indicate the document title, session law, or bill number across pages (e.g., "Senate Bill 403-Ratified", "Session Law 2014-111")
    * Horizontal rules or page break indicators (e.g., "--- PAGE X ---").
    * Signatures and dates at the very end, unless they are part of the main legislative text body.
    * Any other lines consisting solely of symbols, numbers, or repeated short phrases that are clearly not part of the legal text.
7.  **Output Format:** Provide the final output as plain text containing the processed document content with the literal HTML tags applied where appropriate. **Do not escape the angle brackets (`<`, `>`) of the HTML tags as entities (`&lt;`, `&gt;`).**

Please process the provided file and generate the output following these instructions."

This version explicitly tells the model to group contiguous text with the same formatting, which should help resolve the issue you demonstrated with "drug treatment"."""

def scrape_text(pdf_path):
    """
    Scrape text from a PDF file using Google Gemini API and save it as a .txt file.
    
    Args:
        pdf_path (str): The path to the PDF file.
    
    Returns:
        str: The extracted text from the PDF.
    """
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
    df = pd.read_csv("NC/output/nc_bill_text_files.csv")

    pdf_paths = df["pdf_path"].dropna().tolist()
    pdf_paths = [p for p in pdf_paths if os.path.exists(p)]

    logging.info(f"Starting parallel processing on {len(pdf_paths)} files...")

    results = run_in_parallel(pdf_paths, max_workers=4)

    # Save status report to CSV
    status_df = pd.DataFrame(results)
    status_df.to_csv("NC/output/nc_bill_text_status.csv", index=False)

    logging.info("Processing complete. Status written to NC/output/nc_bill_text_status.csv")