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

PROMPT = """IMPORTANT: Output ONLY the text of the uploaded bill with the specified markup. DO NOT summarize, analyze, or add any commentary.

The uploaded PDF is a legislative bill. Your task is to process it as follows:

1. Identify any text with underlining (indicating insertion) and wrap it with: <u class="amendmentInsertedText"> and </u>

2. Identify any text with strikethrough (indicating deletion) and wrap it with: <strike class="amendmentDeletedText"> and </strike>

3. Remove any line numbers appearing in the original document.

4. Output the complete bill text with these markup tags in place.

If the bill contains no underlined or strikethrough text, simply output the plain text of the bill without any markup.

Your response must contain ONLY the processed bill text - no introduction, explanation, or commentary of any kind. You should always try to output the entire text of the bill. Under no circumstances should you output just what was inserted or deleted.

However, please ALWAYS remove this sentence from the text you return: "Stricken language would be deleted from and underlined language would be added to the law as it existed prior to this session of the General Assembly." 

Be particularly attentive to repetitive patterns of formatting in legislative documents. If you see underlining or strikethrough in one instance of similar text, check for the same pattern in related sections.

Examine the full document thoroughly before beginning markup, paying special attention to standard legislative language that appears in multiple sections (like effective date clauses)

When processing legislative documents with formatting that indicates amendments, make multiple passes through the document to ensure all instances of underlining and strikethrough are properly identified.
"""


async def scrape_text(pdf_path, semaphore):
    async with semaphore:
        try:
            await asyncio.sleep(10)  # Initial sleep to respect rate limit

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
                        model="claude-3-7-sonnet-20250219",
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
    df = pd.read_csv("text/state-scrapers/ar_bill_text_files.csv")
    text_dir = Path("/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/arkansas")
    # Regex pattern to remove '_<number>_html.txt' at the end
    pattern = re.compile(r"(_\d+_html\.txt)$")

    existing_uuids = {
        pattern.sub("", f.name) for f in text_dir.rglob("*.txt")
        if pattern.search(f.name)
    }
   
    df = df[~df["UUID"].isin(existing_uuids)]

    pdf_paths = [p for p in df["file_path"].dropna().tolist() if os.path.exists(p)]

    logging.info(f"Processing {len(pdf_paths)} files with async Claude...")

    # Limit to 1 concurrent jobs
    semaphore = asyncio.Semaphore(1)

    tasks = [scrape_text(path, semaphore) for path in pdf_paths]
    results = await asyncio.gather(*tasks)


if __name__ == "__main__":
    asyncio.run(main())
