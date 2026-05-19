#!/usr/bin/env python3
"""Filter the safesql output to rows whose Contact or Household lookup
matches an external id already present in the trainings sandbox, then
emit a CSV ready for `sf data import bulk` with lookup-by-external-id
syntax."""

import csv
import json
import sys
from pathlib import Path

SAFESQL_OUT = "/Users/veevart/tools/safesql/out/tucson-2026-05-19T22-43-45-497Z-7c2abce27771.json"
CONTACT_IDS = "/tmp/im696-upsert/contact-ext-ids.txt"
ACCOUNT_IDS = "/tmp/im696-upsert/account-ext-ids.txt"
OUTPUT_CSV  = "/tmp/im696-upsert/constituent-attributes-filtered.csv"

contact_ids = {line.strip().upper() for line in Path(CONTACT_IDS).read_text().splitlines() if line.strip()}
account_ids = {line.strip().upper() for line in Path(ACCOUNT_IDS).read_text().splitlines() if line.strip()}

print(f"Loaded {len(contact_ids)} contact ext IDs and {len(account_ids)} account ext IDs from sandbox")

with open(SAFESQL_OUT) as f:
    payload = json.load(f)

rows = payload["recordsets"][0]
print(f"Source rows: {len(rows)}")

# CSV headers: use lookup-by-external-id notation for Contact__c and Household_Organization__c
headers = [
    "Implementation_External_ID__c",
    "Contact__r.Auctifera__Implementation_External_ID__c",
    "Household_Organization__r.Auctifera__Implementation_External_ID__c",
    "Attribute_Name__c",
    "Attribute_Group__c",
    "Data_Type__c",
    "Value_Text__c",
    "Value_Boolean__c",
    "Value_Date__c",
    "Value_Number__c",
    "Comment__c",
    "Start_Date__c",
    "End_Date__c",
    "Source_Category_ID__c",
    "Source_Code_Table__c",
]

emitted = 0
skipped_no_match = 0
contact_hits = 0
household_hits = 0
both_hits = 0

with open(OUTPUT_CSV, "w", newline="") as f:
    w = csv.writer(f, quoting=csv.QUOTE_ALL)
    w.writerow(headers)

    for r in rows:
        contact_uuid = (r.get("Contact__c") or "").upper() or None
        hh_uuid      = (r.get("Household_Organization__c") or "").upper() or None

        c_match = contact_uuid in contact_ids if contact_uuid else False
        h_match = hh_uuid in account_ids if hh_uuid else False

        if not c_match and not h_match:
            skipped_no_match += 1
            continue

        if c_match and h_match:
            both_hits += 1
        elif c_match:
            contact_hits += 1
        elif h_match:
            household_hits += 1

        # Booleanos para Salesforce: "1"/"0" -> "true"/"false"; mantenemos null
        bool_val = r.get("Value_Boolean__c")
        if bool_val == "1":
            bool_val = "true"
        elif bool_val == "0":
            bool_val = "false"
        else:
            bool_val = ""

        # Si no hay match en un lado, dejamos esa columna vacia
        w.writerow([
            r["Implementation_External_ID__c"],
            contact_uuid if c_match else "",
            hh_uuid if h_match else "",
            r.get("Attribute_Name__c") or "",
            r.get("Attribute_Group__c") or "",
            r.get("Data_Type__c") or "",
            r.get("Value_Text__c") or "",
            bool_val,
            r.get("Value_Date__c") or "",
            r.get("Value_Number__c") or "",
            r.get("Comment__c") or "",
            r.get("Start_Date__c") or "",
            r.get("End_Date__c") or "",
            r.get("Source_Category_ID__c") or "",
            r.get("Source_Code_Table__c") or "",
        ])
        emitted += 1

print()
print(f"Filtered output:")
print(f"  emitted          = {emitted}")
print(f"  skipped_no_match = {skipped_no_match}")
print(f"  contact_only_hit = {contact_hits}")
print(f"  household_only_hit = {household_hits}")
print(f"  both_hit         = {both_hits}")
print(f"CSV: {OUTPUT_CSV}")
