import Foundation
import PokerDomain

public struct Finding: Hashable, Sendable, CustomStringConvertible {
    public enum Severity: String, Sendable {
        case error, warning
    }

    public enum Rule: String, Sendable {
        case structure, duplicateSpot, replay, heroReach, villainReach, coverage
        case identicalRanges, premiumFold
    }

    public let rule: Rule
    public let severity: Severity
    public let spot: String?
    public let hand: String?
    public let message: String

    public var description: String {
        "[\(severity.rawValue)] \(rule.rawValue) \(spot ?? "-") \(hand ?? ""): \(message)"
    }
}

/// Every rule a book must pass before it can be trusted for drills.
public enum BookValidator {
    private static let premiumHands = ["AA", "KK", "AKs"]

    public static func validate(_ book: RangeBook) -> [Finding] {
        var findings: [Finding] = []
        var spotsByID: [String: Spot] = [:]

        for spot in book.spots {
            if spotsByID[spot.id] != nil {
                findings.append(error(.duplicateSpot, spot: spot.id, "Spot is listed twice"))
            }
            spotsByID[spot.id] = spot
            findings += structureFindings(spot)

            if let key = spot.key {
                if !key.isPlayable {
                    findings.append(error(.replay, spot: spot.id, "The hero is not next to act on this line"))
                }
            } else {
                findings.append(error(.structure, spot: spot.id, "Spot id can't be parsed"))
            }
        }

        for spot in book.spots {
            guard let key = spot.key else { continue }
            findings += reachFindings(spot, key: key, spots: spotsByID)
        }

        if book.book.format == "6max" {
            findings += coverageFindings(Set(spotsByID.keys))
        }
        findings += identicalRangeFindings(book.spots)
        return findings
    }

    /// Every heads-up spot a 6-max book needs. The BB never has an opening decision.
    public static func expectedSixMaxSpots() -> Set<String> {
        var ids = Set<String>()
        func add(_ scenario: ScenarioType, _ hero: Position, _ villain: Position?) {
            if let key = SpotKey(scenario: scenario, hero: hero, villain: villain) { ids.insert(key.id) }
        }

        let seats = Position.preflopSequence
        for hero in seats where hero != .BB { add(.rfi, hero, nil) }
        for (index, first) in seats.enumerated() {
            for second in seats[(index + 1)...] {
                add(.vsRaise, second, first)
                add(.vs3bet, first, second)
                add(.vs4bet, second, first)
                add(.vs5bet, first, second)
            }
        }
        return ids
    }

    private static func structureFindings(_ spot: Spot) -> [Finding] {
        var findings: [Finding] = []
        let codes = spot.options.map(\.code)

        if Set(codes).count != codes.count {
            findings.append(error(.structure, spot: spot.id, "Options repeat a code"))
        }
        for option in spot.options where OptionKind(code: option.code) != option.kind {
            findings.append(error(.structure, spot: spot.id, "Option \(option.code) doesn't match its kind"))
        }
        if !spot.options.contains(where: { $0.kind == .fold }) {
            findings.append(error(.structure, spot: spot.id, "Spot has no fold option"))
        }
        guard spot.grid.count == 13, spot.grid.allSatisfy({ $0.count == 13 }) else {
            findings.append(error(.structure, spot: spot.id, "Grid must be 13 rows of 13 cells"))
            return findings
        }

        for hand in HandGrid.allHands {
            guard let code = spot.code(for: hand) else { continue }
            if code == Spot.mixedCell {
                guard let mix = spot.mix?[hand] else {
                    findings.append(error(.structure, spot: spot.id, hand: hand, "Mixed cell has no frequencies"))
                    continue
                }
                if mix.values.reduce(0, +) != Spot.fullFrequency {
                    findings.append(error(.structure, spot: spot.id, hand: hand, "Frequencies must add up to 100%"))
                }
                if mix.keys.contains(where: { !codes.contains($0) }) || mix.values.contains(where: { $0 < 0 }) {
                    findings.append(error(.structure, spot: spot.id, hand: hand, "Mixed cell uses an unknown option or negative frequency"))
                }
            } else if !codes.contains(code) {
                findings.append(error(.structure, spot: spot.id, hand: hand, "Cell uses unknown option \(code)"))
            } else if spot.mix?[hand] != nil {
                findings.append(error(.structure, spot: spot.id, hand: hand, "Frequencies given for a pure cell"))
            }
        }
        return findings
    }

    private static func reachFindings(_ spot: Spot, key: SpotKey, spots: [String: Spot]) -> [Finding] {
        var findings: [Finding] = []

        for hand in HandGrid.allHands where spot.primaryAction(for: hand) != .fold {
            switch ChartLibrary.reach(of: hand, in: key, spots: spots) {
            case .reached:
                break
            case .notReached:
                findings.append(error(.heroReach, spot: spot.id, hand: hand, "Hero continues with a hand they folded earlier on this line"))
            case .unknown:
                findings.append(warning(.heroReach, spot: spot.id, hand: hand, "Hero's earlier decision isn't in this book"))
            }
        }

        for decision in key.decisions {
            guard let parent = spots[decision.spot.id] else {
                findings.append(warning(.villainReach, spot: spot.id, "No spot for the decision at \(decision.spot.id)"))
                continue
            }
            let kind = OptionKind(decision.kind)
            if !HandGrid.allHands.contains(where: { parent.frequency(of: kind, for: $0) > 0 }) {
                findings.append(error(.villainReach, spot: spot.id, "Nobody takes \(kind.label) at \(decision.spot.id), so this line can't happen"))
            }
        }

        for hand in premiumHands where spot.primaryAction(for: hand) == .fold {
            if ChartLibrary.reach(of: hand, in: key, spots: spots) == .reached {
                findings.append(warning(.premiumFold, spot: spot.id, hand: hand, "Premium hand folds"))
            }
        }
        return findings
    }

    private static func coverageFindings(_ present: Set<String>) -> [Finding] {
        let expected = expectedSixMaxSpots()
        let missing = expected.subtracting(present).sorted().map { error(.coverage, spot: $0, "Spot is missing") }
        let extra = present.subtracting(expected).sorted().map { error(.coverage, spot: $0, "Spot isn't part of a 6-max book") }
        return missing + extra
    }

    private static func identicalRangeFindings(_ spots: [Spot]) -> [Finding] {
        let groups = Dictionary(grouping: spots) { $0.grid }
        return groups.values
            .filter { $0.count > 1 }
            .map { group in
                let ids = group.map(\.id).sorted()
                return warning(.identicalRanges, spot: ids[0], "\(ids.count) spots share one range: \(ids.joined(separator: "  "))")
            }
            .sorted { $0.message < $1.message }
    }

    private static func error(_ rule: Finding.Rule, spot: String, hand: String? = nil, _ message: String) -> Finding {
        Finding(rule: rule, severity: .error, spot: spot, hand: hand, message: message)
    }

    private static func warning(_ rule: Finding.Rule, spot: String, hand: String? = nil, _ message: String) -> Finding {
        Finding(rule: rule, severity: .warning, spot: spot, hand: hand, message: message)
    }
}
