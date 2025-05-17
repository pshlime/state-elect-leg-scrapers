import os
import logging
import base64
from pathlib import Path
import asyncio
import pandas as pd
import re
from anthropic import AsyncAnthropic
from dotenv import load_dotenv

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
load_dotenv()
CLAUDE_APIKEY = os.getenv('CLAUDE_APIKEY')
client = AsyncAnthropic(api_key=CLAUDE_APIKEY)

MAX_RETRIES = 10
RETRY_BACKOFF_BASE = 3

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

Please process the HTML legislative text according to these rules. Please only return the text; do not include any additional explanations or comments. If for some  reason you cannot identify the relevant HTML tags for insertions and deletion, please return all of the legislative text cleaned up and without the HTML formatting.
"""


async def scrape_text(file_path, semaphore):
    async with semaphore:
        try:
            await asyncio.sleep(10)  # Initial sleep to respect rate limit

            logging.info(f"Processing file: {file_path}")

            with open(file_path, "r", encoding="utf-8") as txt_file:
                text_content = txt_file.read()

            messages = [
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": f"{PROMPT}\n\nHere is the legislative text:\n\n{text_content}"},
                    ],
                }
            ]

            for attempt in range(1, MAX_RETRIES + 1):
                try:
                    logging.info(f"Streaming Claude response for: {file_path} (attempt {attempt})")
                    async with client.messages.stream(
                        model="claude-3-7-sonnet-20250219",
                        max_tokens=64000,
                        messages=messages,
                    ) as stream:
                        response_text = ""
                        async for chunk in stream.text_stream:
                            response_text += chunk
                    break  # Exit loop on success
                except Exception as stream_error:
                    logging.warning(f"Stream attempt {attempt} failed for {file_path}: {stream_error}")
                    if attempt == MAX_RETRIES:
                        raise  # Final failure
                    backoff_time = RETRY_BACKOFF_BASE * (attempt + 1)
                    logging.info(f"Retrying in {backoff_time}s...")
                    await asyncio.sleep(backoff_time)

            txt_path = f"{os.path.splitext(file_path)[0]}_html.txt"
            with open(txt_path, "w", encoding="utf-8") as f:
                f.write(response_text)

            logging.info(f"Completed: {file_path}")
            return {"file_path": file_path, "status": "success", "text_path": txt_path}

        except Exception as e:
            logging.error(f"Failed on {file_path}: {e}")
            return {"file_path": file_path, "status": "failed", "error": str(e)}

async def main():
    df = pd.read_csv("AZ/output/az_bill_text_files.csv")
    text_dir = Path("/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/arizona")
    # Regex pattern to remove '_<number>_html.txt' at the end
    pattern = re.compile(r"(_\d+_html\.txt)$")

    existing_uuids = {
        pattern.sub("", f.name) for f in text_dir.rglob("*.txt")
        if pattern.search(f.name)
    }
   
    df = df[~df["UUID"].isin(existing_uuids)]
    file_paths = [p for p in df["file_path"].dropna().tolist() if os.path.exists(p)]

    logging.info(f"Processing {len(file_paths)} files with async Claude...")

    # Limit to 1 concurrent jobs
    semaphore = asyncio.Semaphore(1)

    tasks = [scrape_text(path, semaphore) for path in file_paths]
    results = await asyncio.gather(*tasks)


if __name__ == "__main__":
    asyncio.run(main())
