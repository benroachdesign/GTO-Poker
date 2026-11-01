import Foundation
import Combine
import PokerDomain

public struct PokerRange: Codable, Identifiable, Sendable {
    public var id: String { "\(scenario)_\(hero)_\(villain ?? "")" }

    public let scenario: String
    public let hero: String
    public let villain: String? // Empty string in JSON, usually
    public let ranges: [String: String] // Hand Key (e.g. "AA") -> Action (e.g. "Raise")

    // Computed statistics
    public var stats: RangeStats {
        var raiseCombos = 0.0
        var callCombos = 0.0
        var foldCombos = 0.0

        for (hand, action) in ranges {
            let combos = HandGrid.getCombos(for: hand)
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
}

public struct RangeStats: Sendable {
    public let raise: Double
    public let call: Double
    public let fold: Double

    public init(raise: Double, call: Double, fold: Double) {
        self.raise = raise
        self.call = call
        self.fold = fold
    }
}

@MainActor
public final class RangeManager: ObservableObject {
    @Published private(set) var rangesByKey: [String: PokerRange] = [:]

    public init() {
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

    public func getRange(scenario: String, hero: String, villain: String?) -> PokerRange? {
        let key = PokerRange.makeKey(scenario: scenario, hero: hero, villain: villain)
        return rangesByKey[key]
    }
}
