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
import io


# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
load_dotenv()
CLAUDE_APIKEY = os.getenv('CLAUDE_APIKEY')
client = AsyncAnthropic(api_key=CLAUDE_APIKEY)

MAX_RETRIES = 5
RETRY_BACKOFF_BASE = 3

PROMPT = """IMPORTANT: Output ONLY the text of the uploaded bill with the specified markup. DO NOT summarize, analyze, or add any commentary.

The uploaded PDF is a legislative bill. Your task is to process it as follows:

1. Identify any text with underlining (indicating insertion) and wrap it with: <u class="amendmentInsertedText"> and </u>

2. Identify any text with strikethrough (indicating deletion) and wrap it with: <strike class="amendmentDeletedText"> and </strike>

3. Remove any line numbers appearing in the original document.

4. Output the complete bill text with these markup tags in place.

If the bill contains no underlined or strikethrough text, simply output the plain text of the bill without any markup.

Your response must contain ONLY the processed bill text - no introduction, explanation, or commentary of any kind.
"""

async def scrape_pdf_text(pdf_path, semaphore):
    async with semaphore:
        try:
            await asyncio.sleep(10)  # Initial sleep to respect rate limit

            logging.info(f"Processing PDF in chunks: {pdf_path}")
            CHUNK_SIZE = 35

            reader = PdfReader(pdf_path)
            total_pages = len(reader.pages)
            response_text = ""

            for chunk_start in range(0, total_pages, CHUNK_SIZE):
                chunk_end = min(chunk_start + CHUNK_SIZE, total_pages)

                # Create in-memory chunk
                writer = PdfWriter()
                for i in range(chunk_start, chunk_end):
                    writer.add_page(reader.pages[i])

                buffer = io.BytesIO()
                writer.write(buffer)
                buffer.seek(0)

                base64_string = base64.b64encode(buffer.read()).decode("utf-8")

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
                        logging.info(f"Streaming Claude response for pages {chunk_start + 1}-{chunk_end} (attempt {attempt})")
                        async with client.messages.stream(
                            model="claude-3-7-sonnet-20250219",
                            max_tokens=64000,
                            messages=messages,
                        ) as stream:
                            chunk_text = ""
                            async for chunk in stream.text_stream:
                                chunk_text += chunk
                        response_text += chunk_text + "\n"
                        break  # success
                    except Exception as stream_error:
                        logging.warning(f"Stream attempt {attempt} failed for chunk {chunk_start + 1}-{chunk_end}: {stream_error}")
                        if attempt == MAX_RETRIES:
                            raise
                        backoff_time = RETRY_BACKOFF_BASE * (attempt + 1)
                        logging.info(f"Retrying in {backoff_time}s...")
                        await asyncio.sleep(backoff_time)

            # Save final combined response
            txt_path = f"{os.path.splitext(pdf_path)[0]}_html.txt"
            with open(txt_path, "w", encoding="utf-8") as f:
                f.write(response_text)

            logging.info(f"Completed full PDF: {pdf_path}")

        except Exception as e:
            logging.error(f"Failed on {pdf_path}: {e}")


def sync_scrape_text(pdf_path_str):
    import asyncio
    semaphore = asyncio.Semaphore(1)
    result = asyncio.run(scrape_pdf_text(pdf_path_str, semaphore))
    return result
