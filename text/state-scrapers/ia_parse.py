import os
import logging
import base64
from pathlib import Path
import asyncio
import pandas as pd
import re
from anthropic import AsyncAnthropic
from dotenv import load_dotenv
from PyPDF2 import PdfReader, PdfWriter

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
load_dotenv()
CLAUDE_APIKEY = os.getenv('CLAUDE_APIKEY')
client = AsyncAnthropic(api_key=CLAUDE_APIKEY)

MAX_RETRIES = 10
RETRY_BACKOFF_BASE = 3

PROMPT = """IMPORTANT: Output ONLY the text of the uploaded bill with the specified markup. DO NOT summarize, analyze, or add any commentary.

The uploaded PDF is a legislative bill. Your task is to process it as follows:

1. Identify any text with underlining (indicating insertion) and wrap it with: <u class="amendmentInsertedText"> and </u>

2. Identify any text with strikethrough (indicating deletion) and wrap it with: <strike class="amendmentDeletedText"> and </strike>

3. Remove any line numbers appearing in the original document.

4. Output the complete bill text with these markup tags in place.

5. Remove standard legislative boilerplate including filing information, sponsor names, vote tallies, approval lines, and any other procedural text that appears before the actual bill content.

If the bill contains no underlined or strikethrough text, simply output the plain text of the bill without any markup.

Your response must contain ONLY the processed bill text - no introduction, explanation, or commentary of any kind. You should always try to output the entire text of the bill. Under no circumstances should you output just what was inserted or deleted.

When processing legislative documents with formatting that indicates amendments, make multiple passes through the document to ensure all instances of underlining and strikethrough are properly identified.
"""


async def scrape_text(pdf_path, semaphore):
    async with semaphore:
        try:
            await asyncio.sleep(10)  # Initial sleep to respect rate limit

            reader = PdfReader(pdf_path)
            total_pages = len(reader.pages)

            if total_pages > 40:
                logging.info(f"Skipping {pdf_path}: too long ({total_pages} pages)")
                return None
            
            else:
            
                logging.info(f"Uploading PDF file: {pdf_path}")
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
                        logging.info(f"Streaming Claude response for: {pdf_path} (attempt {attempt})")
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
                        logging.warning(f"Stream attempt {attempt} failed for {pdf_path}: {stream_error}")
                        if attempt == MAX_RETRIES:
                            raise  # Final failure
                        backoff_time = RETRY_BACKOFF_BASE * (attempt + 1)
                        logging.info(f"Retrying in {backoff_time}s...")
                        await asyncio.sleep(backoff_time)

                txt_path = f"{os.path.splitext(pdf_path)[0]}_html.txt"
                with open(txt_path, "w", encoding="utf-8") as f:
                    f.write(response_text)

                logging.info(f"Completed: {pdf_path}")
                return {"pdf_path": pdf_path, "status": "success", "text_path": txt_path}

        except Exception as e:
            logging.error(f"Failed on {pdf_path}: {e}")
            return {"pdf_path": pdf_path, "status": "failed", "error": str(e)}

async def main():
    df = pd.read_csv("text/state-scrapers/ia_bill_text_files.csv")

    pdf_paths = [p for p in df["file_path"].dropna().tolist() if os.path.exists(p)]

    logging.info(f"Processing {len(pdf_paths)} files with async Claude...")

    # Limit to 1 concurrent jobs
    semaphore = asyncio.Semaphore(2)

    tasks = [scrape_text(path, semaphore) for path in pdf_paths]
    results = await asyncio.gather(*tasks)


if __name__ == "__main__":
    asyncio.run(main())
