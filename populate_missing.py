import json
import os

JSON_PATH = 'GTOPoker/Resources/poker_ranges.json'

def populate():
    with open(JSON_PATH, 'r') as f:
        data = json.load(f)
    
    # Template to copy logic from (we'll use a blank template with all Folds for safety, 
    # or just copy the keys from the first entry to ensure we have all hands)
    
    template_ranges = data[0]['ranges'].copy()
    for k in template_ranges:
        template_ranges[k] = "Fold" # Default to Fold
        
    # Specific missing entry to add
    missing_entries = [
        {"scenario": "vs 4bet", "hero": "BB", "villain": "CO"}
    ]
    
    added_count = 0
    
    for missing in missing_entries:
        # Check if already exists
        exists = False
        for entry in data:
            if (entry.get('scenario') == missing['scenario'] and 
                entry.get('hero') == missing['hero'] and 
                entry.get('villain') == missing['villain']):
                exists = True
                break
        
        if not exists:
            new_entry = {
                "scenario": missing['scenario'],
                "hero": missing['hero'],
                "villain": missing['villain'],
                "ranges": template_ranges.copy() # All Folds
            }
            data.append(new_entry)
            print(f"Added: {missing}")
            added_count += 1
        else:
            print(f"Already exists: {missing}")

    if added_count > 0:
        with open(JSON_PATH, 'w') as f:
            json.dump(data, f, indent=2)
        print(f"Successfully added {added_count} entries.")
    else:
        print("No new entries added.")

if __name__ == "__main__":
    populate()
