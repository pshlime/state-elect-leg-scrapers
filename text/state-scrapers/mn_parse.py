import os
import logging
import base64
from pathlib import Path
import asyncio
import pandas as pd
import re
from anthropic import AsyncAnthropic
from dotenv import load_dotenv
from striprtf.striprtf import rtf_to_text
import tempfile
import subprocess
import platform

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
load_dotenv()
CLAUDE_APIKEY = os.getenv('CLAUDE_APIKEY')
client = AsyncAnthropic(api_key=CLAUDE_APIKEY)

MAX_RETRIES = 4
RETRY_BACKOFF_BASE = 3

PROMPT = """IMPORTANT: Output ONLY the text of the uploaded bill with the specified markup. DO NOT summarize, analyze, or add any commentary.
The uploaded pdf is a legislative bill. Your task is to process it as follows:
1. Identify any text with underlining (indicating insertion) and wrap it with: <u class="amendmentInsertedText"> and </u>
2. Identify any text with strikethrough (indicating deletion) and wrap it with: <strike class="amendmentDeletedText"> and </strike>
3. Remove any line numbers appearing in the original document.
4. Output the complete bill text with these markup tags in place.

If the bill contains no underlined or strikethrough text, simply output the plain text of the bill without any markup.

For substantial insertions or deletions that span multiple lines or paragraphs, identify the beginning and end of the entire amended block. Wrap the whole block with a single set of <u class="amendmentInsertedText"> and </u> tags (for insertions) or <strike class="amendmentDeletedText"> and </strike> tags (for deletions). Do not tag each line individually if they are part of the same continuous inserted or deleted section.

Your response must contain ONLY the processed bill text - no introduction, explanation, or commentary of any kind."""

def convert_rtf_to_pdf(rtf_path):
    """Convert RTF file to PDF using LibreOffice headless mode"""
    try:
        with tempfile.TemporaryDirectory() as temp_dir:
            # Determine LibreOffice path based on OS
            if platform.system() == "Darwin":  # macOS
                libreoffice_cmd = "/Applications/LibreOffice.app/Contents/MacOS/soffice"
            elif platform.system() == "Linux":
                libreoffice_cmd = "libreoffice"
            elif platform.system() == "Windows":
                libreoffice_cmd = "soffice"
            else:
                libreoffice_cmd = "libreoffice"
            
            # Check if LibreOffice exists
            if platform.system() == "Darwin" and not os.path.exists(libreoffice_cmd):
                logging.error(f"LibreOffice not found at {libreoffice_cmd}")
                return None
            
            # Use LibreOffice to convert RTF to PDF
            cmd = [
                libreoffice_cmd, '--headless', '--convert-to', 'pdf',
                '--outdir', temp_dir, rtf_path
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
            
            if result.returncode != 0:
                logging.error(f"LibreOffice conversion failed: {result.stderr}")
                return None
            
            # Find the generated PDF
            pdf_filename = Path(rtf_path).stem + '.pdf'
            pdf_path = os.path.join(temp_dir, pdf_filename)
            
            if os.path.exists(pdf_path):
                # Move the PDF to the same directory as the RTF file
                output_pdf_path = os.path.join(os.path.dirname(rtf_path), pdf_filename)
                os.rename(pdf_path, output_pdf_path)
                return output_pdf_path
            else:
                logging.error(f"PDF file not created: {pdf_path}")
                return None
                
    except subprocess.TimeoutExpired:
        logging.error(f"LibreOffice conversion timeout for {rtf_path}")
        return None
    except Exception as e:
        logging.error(f"Error converting {rtf_path} to PDF: {e}")
        return None

async def scrape_text(rtf_path, semaphore):
    async with semaphore:
        try:
            await asyncio.sleep(10)  # Initial sleep to respect rate limit
            
            # Convert RTF to PDF
            logging.info(f"Converting RTF to PDF: {rtf_path}")
            pdf_path = convert_rtf_to_pdf(rtf_path)
            
            if not pdf_path:
                logging.error(f"Failed to convert {rtf_path} to PDF")
                return {"rtf_path": rtf_path, "status": "failed", "error": "RTF to PDF conversion failed"}
            
            logging.info(f"Uploading converted PDF file: {pdf_path}")
            with open(pdf_path, "rb") as pdf_file:
                base64_string = base64.b64encode(pdf_file.read()).decode("utf-8")

            messages = [
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "document",
                            "source": {
                                "type": "base64",
                                "media_type": "application/pdf",
                                "data": base64_string,
                            },
                        },
                        {"type": "text", "text": PROMPT},
                    ],
                }
            ]

            for attempt in range(1, MAX_RETRIES + 1):
                try:
                    logging.info(f"Streaming Claude response for: {rtf_path} (attempt {attempt})")
                    async with client.messages.stream(
                        model="claude-4-sonnet-20250514",
                        max_tokens=64000,
                        messages=messages,
                    ) as stream:
                        response_text = ""
                        async for chunk in stream.text_stream:
                            response_text += chunk
                    break  # Exit loop on success
                except Exception as stream_error:
                    logging.warning(f"Stream attempt {attempt} failed for {rtf_path}: {stream_error}")
                    if attempt == MAX_RETRIES:
                        raise  # Final failure
                    backoff_time = RETRY_BACKOFF_BASE * (attempt + 1)
                    logging.info(f"Retrying in {backoff_time}s...")
                    await asyncio.sleep(backoff_time)

            txt_path = f"{os.path.splitext(rtf_path)[0]}_html.txt"
            with open(txt_path, "w", encoding="utf-8") as f:
                f.write(response_text)

            logging.info(f"Completed: {rtf_path}")
            return {"rtf_path": rtf_path, "status": "success", "text_path": txt_path}

        except Exception as e:
            logging.error(f"Failed on {rtf_path}: {e}")
            return {"rtf_path": rtf_path, "status": "failed", "error": str(e)}

async def main():
    # Update to look for RTF files instead of PDF files
    df = pd.read_csv("text/state-scrapers/mn_bill_text_files.csv")
    
    text_dir = Path("/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/minnesota")
    # Regex pattern to remove '_<number>_html.txt' at the end
    existing_uuids = {
        f.parent.name for f in text_dir.rglob("*_html.txt")
    }
   
    df = df[~df["UUID"].isin(existing_uuids)]

    rtf_paths = [p for p in df["file_path"].dropna().tolist() if os.path.exists(p) and p.lower().endswith('.rtf')]

    logging.info(f"Processing {len(rtf_paths)} RTF files with async Claude...")

    # Limit to 5 concurrent jobs
    semaphore = asyncio.Semaphore(5)

    tasks = [scrape_text(path, semaphore) for path in rtf_paths]
    results = await asyncio.gather(*tasks)

if __name__ == "__main__":
    asyncio.run(main())
    