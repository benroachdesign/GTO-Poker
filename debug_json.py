import json
import sys

def check_scenarios(hero, villain):
    with open('GTOPoker/Resources/poker_ranges.json', 'r') as f:
        data = json.load(f)
    
    found = []
    for entry in data:
        if entry.get('hero') == hero and entry.get('villain') == villain:
            found.append(entry.get('scenario'))
    
    print(f"Scenarios for Hero {hero} vs Villain {villain}:")
    for s in found:
        print(f"- {s}")

if __name__ == "__main__":
    check_scenarios("BB", "CO")
