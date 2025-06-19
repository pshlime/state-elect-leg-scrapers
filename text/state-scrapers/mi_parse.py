import os
import logging
import base64
from pathlib import Path
import asyncio
import pandas as pd
import re
import shutil
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
The html below is a legislative bill from Michigan. The bill uses the following markup rules:
* New language in an amendatory bill will be shown in bold
* Language to be removed will be striken and may appear as ~~strikethrough~~ or <s>strikethrough</s>
* Amendments made by the House will be [blue with square brackets]
* Amendments made by the Senate will be <red with angle brackets>

Your task is to process it as follows:
1. Identify any language inserted in existing law and wrap it with: <u class="amendmentInsertedText"> and </u>
2. Identify any language deleted from existing law and wrap it with: <strike class="amendmentDeletedText"> and </strike>
3. Remove all line numbers (appearing as numbers at the start of lines, like "1", "2", "3", etc.)
4. Output the complete bill text with these markup tags in place. Clean up any residual HTML or markdown formatting artifacts after following the previous steps.

Your response must contain ONLY the processed bill text - no introduction, explanation, or commentary of any kind.

The text of the bill is as follows:
"""

def find_existing_processed_file(file_path, text_dir):
    """Find an existing processed file with the same basename in any subdirectory"""
    basename = Path(file_path).name  # e.g., "2001-HIB-5116_v1.txt"
    processed_basename = f"{Path(basename).stem}_processed.txt"  # e.g., "2001-HIB-5116_v1_processed.txt"
    
    # Search for any existing processed file with this basename
    for processed_file in text_dir.rglob(processed_basename):
        logging.info(f"Found existing processed file: {processed_file}")
        return processed_file
    
    return None

async def scrape_text(file_path, semaphore, text_dir):
    async with semaphore:
        try:
            output_path = f"{os.path.splitext(file_path)[0]}_processed.txt"
            
            # Check if this specific processed file already exists
            if os.path.exists(output_path):
                logging.info(f"Processed file already exists: {output_path}")
                return {"file_path": file_path, "status": "already_exists", "text_path": output_path}
            
            # Check if we can copy from an existing processed file with same basename
            existing_processed = find_existing_processed_file(file_path, text_dir)
            if existing_processed:
                logging.info(f"Copying existing processed file from {existing_processed} to {output_path}")
                shutil.copy2(existing_processed, output_path)
                return {"file_path": file_path, "status": "copied", "text_path": output_path, "copied_from": str(existing_processed)}
            
            # If no existing processed file found, process with Claude API
            await asyncio.sleep(10)  # Initial sleep to respect rate limit

            # Read the text file
            with open(file_path, "r", encoding="utf-8") as txt_file:
                text_content = txt_file.read()
            
            logging.info(f"Processing text file with Claude API: {file_path}")

            messages = [
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": f"{PROMPT}\n{text_content}"},
                    ],
                }
            ]

            for attempt in range(1, MAX_RETRIES + 1):
                try:
                    logging.info(f"Streaming Claude response for: {file_path} (attempt {attempt})")
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
                    logging.warning(f"Stream attempt {attempt} failed for {file_path}: {stream_error}")
                    if attempt == MAX_RETRIES:
                        raise  # Final failure
                    backoff_time = RETRY_BACKOFF_BASE * (attempt + 1)
                    logging.info(f"Retrying in {backoff_time}s...")
                    await asyncio.sleep(backoff_time)

            with open(output_path, "w", encoding="utf-8") as f:
                f.write(response_text)

            logging.info(f"Completed API processing: {file_path}")
            return {"file_path": file_path, "status": "processed", "text_path": output_path}

        except Exception as e:
            logging.error(f"Failed on {file_path}: {e}")
            return {"file_path": file_path, "status": "failed", "error": str(e)}
        
async def main():
    df = pd.read_csv("text/state-scrapers/mi_bill_text_files.csv")
    text_dir = Path("/Users/josephloffredo/MIT Dropbox/Joseph Loffredo/election_bill_text/data/michigan")

    file_paths = [p for p in df["file_path"].dropna().tolist() if os.path.exists(p)]

    logging.info(f"Processing {len(file_paths)} files with async Claude...")

    # Limit to 5 concurrent jobs
    semaphore = asyncio.Semaphore(5)

    tasks = [scrape_text(path, semaphore, text_dir) for path in file_paths]
    results = await asyncio.gather(*tasks)

if __name__ == "__main__":
    asyncio.run(main())