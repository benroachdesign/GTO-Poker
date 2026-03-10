import Foundation

struct PokerRange: Codable, Identifiable {
    var id: String { "\(scenario)_\(hero)_\(villain ?? "")" }
    
    let scenario: String
    let hero: String
    let villain: String? // Empty string in JSON, usually
    let ranges: [String: String] // Hand Key (e.g. "AA") -> Action (e.g. "Raise")
    
    // Computed statistics
    var stats: RangeStats {
        var raiseCombos = 0.0
        var callCombos = 0.0
        var foldCombos = 0.0
        
        for (hand, action) in ranges {
            let combos = PokerRange.getCombos(for: hand)
            switch action {
            case "Raise", "All-in": raiseCombos += combos
            case "Call": callCombos += combos
            default: foldCombos += combos
            }
        }
        
        let total = raiseCombos + callCombos + foldCombos
        // If total is 0 (empty range), avoid div by zero
        if total == 0 { return RangeStats(raise: 0, call: 0, fold: 0) }
        
        return RangeStats(
            raise: (raiseCombos / total) * 100,
            call: (callCombos / total) * 100,
            fold: (foldCombos / total) * 100
        )
    }
    
    var lookupKey: String {
        PokerRange.makeKey(scenario: scenario, hero: hero, villain: villain)
    }

    static func makeKey(scenario: String, hero: String, villain: String?) -> String {
        "\(scenario.lowercased())_\(hero.lowercased())_\(villain?.lowercased() ?? "")"
    }

    static func getCombos(for hand: String) -> Double {
        // Pairs: 6 combos (AA, KK...)
        if hand.count == 2 && hand.first == hand.last { return 6.0 }
        // Suited: 4 combos (AKs...)
        if hand.hasSuffix("s") { return 4.0 }
        // Offsuit: 12 combos (AKo...)
        if hand.hasSuffix("o") { return 12.0 }
        return 0.0
    }
}

struct RangeStats {
    let raise: Double
    let call: Double
    let fold: Double
}

class RangeManager: ObservableObject {
    @Published private var rangesByKey: [String: PokerRange] = [:]

    init() {
        loadRanges()
    }

    func loadRanges() {
        guard let url = Bundle.module.url(forResource: "poker_ranges", withExtension: "json") else {
            print("poker_ranges.json not found in bundle")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let ranges = try JSONDecoder().decode([PokerRange].self, from: data)
            rangesByKey = Dictionary(uniqueKeysWithValues: ranges.map { ($0.lookupKey, $0) })
            print("Loaded \(rangesByKey.count) ranges")
        } catch {
            print("Failed to decode ranges: \(error)")
        }
    }

    func getRange(scenario: String, hero: String, villain: String?) -> PokerRange? {
        let key = PokerRange.makeKey(scenario: scenario, hero: hero, villain: villain)
        return rangesByKey[key]
    }
}
