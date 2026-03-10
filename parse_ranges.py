import csv
import json

RANK_MAP = ['A', 'K', 'Q', 'J', 'T', '9', '8', '7', '6', '5', '4', '3', '2']

def get_hand_name(row_idx, col_idx):
    """
    Returns the hand name for a given row and column index.
    Row and Col 0 correspond to 'A', 1 to 'K', etc.
    r == c -> Pair (e.g., AA)
    r < c  -> Suited (RowCard + ColCard + 's') e.g., 0,1 -> AKs
    r > c  -> Offsuit (ColCard + RowCard + 'o') e.g., 1,0 -> AKo
    """
    rank1 = RANK_MAP[row_idx]
    rank2 = RANK_MAP[col_idx]
    
    if row_idx == col_idx:
        return f"{rank1}{rank2}"
    elif row_idx < col_idx:
        return f"{rank1}{rank2}s"
    else:
        return f"{rank2}{rank1}o"

def parse_action(value):
    val = value.strip().upper()
    if val == 'R':
        return 'Raise'
    elif val == 'C':
        return 'Call'
    elif val == 'A': # All-in sometimes? Assuming standard R/C/F based on prompt
        return 'All-in'
    else:
        return 'Fold'

def parse_csv(filename):
    ranges_data = []
    
    with open(filename, 'r', encoding='utf-8-sig') as f:
        reader = list(csv.reader(f))
        
    i = 0
    while i < len(reader):
        row = reader[i]
        
        # Look for the start of a block
        if len(row) > 0 and row[0] == "Players":
            # Metadata is on the next line (i+1)
            meta_row_idx = i + 1
            if meta_row_idx >= len(reader):
                break
            
            meta_row = reader[meta_row_idx]
            
            # Extract metadata
            # Columns: Scenario (Col C -> idx 2), Hero (Col D -> idx 3), Villain (Col E -> idx 4)
            scenario = meta_row[2]
            hero = meta_row[3]
            villain = meta_row[4]
            
            # Initialize range map for this block
            hand_actions = {}
            
            # The grid starts at meta_row_idx (which is the first row of the grid, corresponding to 'Ao' label but Row 0 of ranks)
            # Actually, let's verify row labels.
            # Row labels in CSV column F are 'Ao', 'Ko'... 
            # Row 0 of the grid is the meta_row itself?
            # Let's check the CSV content again.
            # meta_row has 'Ao' in column F. So yes, meta_row is the first row of data.
            
            for r in range(13):
                current_row_idx = meta_row_idx + r
                if current_row_idx >= len(reader):
                    break
                
                grid_row = reader[current_row_idx]
                
                # Columns G (6) to S (18)
                for c in range(13):
                    csv_col_idx = 6 + c
                    if csv_col_idx < len(grid_row):
                        cell_val = grid_row[csv_col_idx]
                    else:
                        cell_val = ""
                        
                    action = parse_action(cell_val)
                    hand_name = get_hand_name(r, c)
                    
                    # Only store non-fold actions to save space? 
                    # User asked for "clean poker_ranges.json". 
                    # Usually explicit is better, but "F" is default.
                    # User spec: Values: "R"="Raise", "C"="Call", "F"(or empty)="Fold".
                    hand_actions[hand_name] = action
            
            ranges_data.append({
                "scenario": scenario,
                "hero": hero,
                "villain": villain,
                "ranges": hand_actions
            })
            
            # Skip past this block
            # Block is header + 13 rows.
            # But the loop increments i. We need to jump 14 rows (1 header + 13 data).
            i += 14
        else:
            i += 1
            
    return ranges_data

if __name__ == "__main__":
    csv_file = "GTO Preflop Ranges - POKER TRAINER RANGES.csv"
    output_file = "poker_ranges.json"
    
    try:
        data = parse_csv(csv_file)
        with open(output_file, 'w') as f:
            json.dump(data, f, indent=2)
        print(f"Successfully created {output_file} with {len(data)} scenarios.")
    except Exception as e:
        print(f"Error: {e}")
