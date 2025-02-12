import pandas as pd
import json
import configparser
import logging
from openai import OpenAI
import os
from datetime import datetime
from pydantic import BaseModel
from typing import List, Optional

class RollCallVote(BaseModel):
    yea: List[str]
    nay: List[str]
    present: List[str]
    absent: List[str]

class RollCallResponse(BaseModel):
    voteQuestion: str
    voteDate: str
    voteType: str
    rollCallVote: RollCallVote

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# Load environment variables from the .env file
from dotenv import load_dotenv
load_dotenv()
OPENAI_APIKEY = os.getenv('OPENAI_APIKEY')

# Initialize OpenAI client
client = OpenAI(api_key=OPENAI_APIKEY)

SYSTEM_PROMPT = """You will be given pages from the journal of the Texas state legislature.
For the given bill, your task is to retrieve the list of names for legislators that vote yes, no, present, or who are absent from the vote.
In addition, to the list of legislators, you should provide the question being asked to legislators.
You should also get the date of the vote.
You should also tell me how the vote was taken (e.g. by record vote, by viva voce, etc.).

If you see something like "The bill was read second time and was passed to engrossment by a viva voce vote. All Members are deemed to have voted "Yea" on the passage to engrossment.", 
then the question would be "On the second reading", the voteType would be "viva voce", and there is no need to list out the names of who voted yea, nay, present, or absent.

Output the results in JSON format.

Here is an example: 
Text: "FORTY-SEVENTH DAY — THURSDAY, APRIL 9, 2009 
HB 205 ON THIRD READING (by Aycock)
HB 205, A bill to be entitled An Act relating to the applicability of certain city requirements affecting the restraint of certain dogs on annexed or otherwise acquired property used for agricultural operations.
HBi205 was passed by (Record 146): 147 Yeas, 0 Nays, 1 Present, not voting.
Yeas — Allen; Alonzo; Alvarado; Anchia; Anderson; Aycock; Berman; Bohac; Bolton; Bonnen; Branch; Brown.
Nays - Farias; Farrar; Fletcher; Flores; Flynn; Frost; Gallego; Gattis; Geren; Giddings
Present, not voting - Castro
Absent - Pierson" 
Output: 
  voteQuestion = ["On third reading"]
  voteDate = ["April 9, 2009"]
  voteType = ["record vote"]
  yea = ["Allen", "Alonzo", "Alvarado", "Anchia", "Anderson", "Aycock", "Berman", "Bohac", "Bolton", "Bonnen", "Branch", "Brown"]
  nay = ["Farias", "Farrar", "Fletcher", "Flores", "Flynn", "Frost", "Gallego", "Gattis", "Geren", "Giddings"]
  present = ["Castro"]
  absent = ["Pierson"]
  
Text: "SENATE JOURNAL
 EIGHTY-FIRST LEGISLATURE — REGULAR SESSION
 AUSTIN, TEXAS
 PROCEEDINGS
 FORTY-SEVENTH DAY
 (Continued)
 (Thursday, April 30, 2009)

Pursuant to Senate Rule 9.03(d), the following bills and resolutions were laid before the Senate in the order listed, read second time, amended where applicable, passed to engrossment or third reading, read third time, and passed. The votes on passage to engrossment or third reading, suspension of the Constitutional Three-day Rule, and final passage are indicated after each caption. All Members are deemed to have voted "Yea" on viva voce votes unless otherwise indicated.

SB 212 (Shapleigh)
Relating to the sale or transportation of certain desert plants; providing a penalty. (viva voce vote) (31-0) (31-0)
"
Output:
  voteQuestion = ["On second reading, third reading, and final passage"]
  voteDate = ["April 30, 2009"]
  voteType = ["viva voce"]
  yea = []
  nay = []
  present = []
  absent = []
"""

def parse_rollcall(text, bill_number, bill_number_full):
    """Parse the journal and return the roll call vote for the given bill."""
    logging.info("Calling OpenAI API to parse journal.")
    completion = client.beta.chat.completions.parse(
      model="gpt-4o-mini",
      temperature=0,
      messages=[
        {"role": "developer", "content": SYSTEM_PROMPT},
        {"role": "user", "content": f"List the roll call vote for {bill_number} ({bill_number_full}). Here is the committee report: {text}"}
      ],
      response_format = RollCallResponse
    )
    
    output = {
    "voteQuestion": completion.choices[0].message.parsed.voteQuestion,
    "voteDate": completion.choices[0].message.parsed.voteDate,
    "voteType": completion.choices[0].message.parsed.voteType,
    "yea": completion.choices[0].message.parsed.rollCallVote.yea,
    "nay": completion.choices[0].message.parsed.rollCallVote.nay,
    "present": completion.choices[0].message.parsed.rollCallVote.present,
    "absent": completion.choices[0].message.parsed.rollCallVote.absent}
    
    return {"id": completion.id, "response": output, "tokens": completion.usage.total_tokens}
    
