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

PROMPT = """I've uploaded a legislative bill in PDF format. Please analyze this document and properly mark text that has been inserted or deleted in the amendment process.

In legislative bills, inserted text is typically indicated by underlining, and deleted text is typically shown with strikethrough formatting.

Instructions:
1. Examine the PDF carefully, noting any text that appears with underlining (indicating insertion) or strikethrough (indicating deletion).
2. For all underlined text that represents insertions, wrap it with: <u class="amendmentInsertedText"> and </u>
3. For all text with strikethrough that represents deletions, wrap it with: <strike class="amendmentDeletedText"> and </strike>
4. Present the complete text of the bill with these markup tags in place.
5. Remove any line numbers that appear in the original document.
6. Pay particular attention to Section 1 where amendments to existing code sections are typically described.

Please output the complete bill text as written with proper markup for the inserted and deleted portions. If there is no insertion or deletion, simply return the plain text of the bill without any markup.

By no means should you attempt to summarize or interpret the bill. Your task is parse the text and include the desired formatting as appropriate.

Please do not include any additional introduction, commentary, or explanation in your response. Just provide the text with the specified markup.
"""


async def scrape_text(pdf_path, semaphore):
    async with semaphore:
        try:
            await asyncio.sleep(10)  # Wait ~10s between tasks to avoid rate limit

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

            logging.info(f"Streaming Claude response for: {pdf_path}")
            async with client.messages.stream(
                model="claude-3-7-sonnet-20250219",
                max_tokens=64000,
                messages=messages,
            ) as stream:
                response_text = ""
                async for chunk in stream.text_stream:
                    response_text += chunk

            txt_path = f"{os.path.splitext(pdf_path)[0]}_html.txt"
            with open(txt_path, "w", encoding="utf-8") as f:
                f.write(response_text)

            logging.info(f"Completed: {pdf_path}")
            return {"pdf_path": pdf_path, "status": "success", "text_path": txt_path}

        except Exception as e:
            logging.error(f"Failed on {pdf_path}: {e}")
            return {"pdf_path": pdf_path, "status": "failed", "error": str(e)}


async def main():
    df = pd.read_csv("GA/output/ga_bill_text_links.csv")
    text_dir = Path("/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/georgia")
    # Regex pattern to remove '_<number>_html.txt' at the end
    pattern = re.compile(r"(_\d+_html\.txt)$")

    existing_uuids = {
        pattern.sub("", f.name) for f in text_dir.rglob("*.txt")
        if pattern.search(f.name)
    }
   
    df = df[~df["uuid"].isin(existing_uuids)]
    pdf_paths = [p for p in df["pdf_path"].dropna().tolist() if os.path.exists(p)]

    logging.info(f"Processing {len(pdf_paths)} files with async Claude...")

    # Limit to 2 concurrent jobs
    semaphore = asyncio.Semaphore(1)

    tasks = [scrape_text(path, semaphore) for path in pdf_paths]
    results = await asyncio.gather(*tasks)


if __name__ == "__main__":
    asyncio.run(main())
