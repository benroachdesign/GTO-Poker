import Foundation
import Combine
import PokerDomain

public struct PokerRange: Identifiable, Sendable {
    public let id: String
    public let ranges: [String: String] // Hand Key (e.g. "AA") -> Action (e.g. "Raise")

    public init(spot: Spot) {
        id = spot.id
        var ranges: [String: String] = [:]
        for hand in HandGrid.allHands {
            ranges[hand] = spot.primaryAction(for: hand).label
        }
        self.ranges = ranges
    }

    private init(id: String, ranges: [String: String]) {
        self.id = id
        self.ranges = ranges
    }

    /// What the range's aggressive action is called. Spots facing a 4-bet shove rather than raise.
    public var aggressiveLabel: String {
        ranges.values.contains(OptionKind.allIn.label) ? OptionKind.allIn.label : OptionKind.raise.label
    }

    /// This range as it was before a repair.
    public func reverting(_ changes: [CellChange]) -> PokerRange {
        var ranges = ranges
        for change in changes {
            ranges[change.hand] = OptionKind(code: change.was)?.label
        }
        return PokerRange(id: "\(id)#before", ranges: ranges)
    }

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
    @Published public private(set) var library: ChartLibrary?
    @Published public private(set) var loadError: String?
    private var rangesByID: [String: PokerRange] = [:]

    public init() {}

    /// Decodes the bundled book off the main actor, so launch never waits on it.
    public func load() async {
        guard library == nil else { return }

        let clock = ContinuousClock()
        let start = clock.now
        do {
            let (library, ranges) = try await Task.detached(priority: .userInitiated) {
                let library = try ChartLibrary.bundled()
                let ranges = library.book.spots.map { PokerRange(spot: $0) }
                return (library, ranges)
            }.value

            rangesByID = Dictionary(uniqueKeysWithValues: ranges.map { ($0.id, $0) })
            self.library = library
            print("Loaded \(ranges.count) spots in \(clock.now - start)")
        } catch {
            loadError = String(describing: error)
            print("Failed to load ranges: \(error)")
        }
    }

    public func getRange(scenario: ScenarioType, hero: Position, villain: Position?) -> PokerRange? {
        guard let key = SpotKey(scenario: scenario, hero: hero, villain: villain) else { return nil }
        return rangesByID[key.id]
    }

    public func range(forSpot id: String) -> PokerRange? {
        rangesByID[id]
    }
}
