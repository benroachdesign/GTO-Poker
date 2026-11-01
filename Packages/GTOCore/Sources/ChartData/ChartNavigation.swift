import Foundation
import PokerDomain

/// One thing the hero can do at a spot, ready to show.
public struct SpotChoice: Identifiable, Sendable {
    public let kind: OptionKind
    public let code: String
    public let title: String
    public let sizeBB: Double?
    public let share: Double // Fraction of the hands that reach this spot
    public let destination: SpotKey? // Nil when the book has nothing further down this path

    public var id: OptionKind { kind }
}

/// One action already taken on the line.
public struct LineEntry: Identifiable, Sendable {
    public let spot: SpotKey // Where the player made this decision
    public let kind: OptionKind
    public let title: String
    public let sizeBB: Double?

    public var id: String { spot.id }
    public var position: Position { spot.hero }
}

public enum SeatStatus: Hashable, Sendable {
    case toAct
    case acted(OptionKind)
    case waiting
    case folded
}

public struct TableSeat: Identifiable, Sendable {
    public let position: Position
    public let status: SeatStatus
    public let bet: Double

    public var id: Position { position }
}

public struct TableState: Sendable {
    public let hero: Position
    public let seats: [TableSeat]
    public let pot: Double
    public let toCall: Double
}

/// What a hand did at one of the hero's decisions.
public struct HandStep: Identifiable, Sendable {
    public let spot: SpotKey
    public let action: OptionKind?  // Nil if the hand never got this far
    public let title: String
    public let sizeBB: Double?
    public let isCurrent: Bool

    public var id: String { spot.id }
}

/// How one hand plays at the same point in other matchups.
public struct HandComparison: Sendable {
    public struct Entry: Identifiable, Sendable {
        public let spot: SpotKey
        public let seat: Position
        public let action: OptionKind?
        public let isCurrent: Bool

        public var id: String { spot.id }
    }

    public let title: String
    public let entries: [Entry]
}

extension SpotKey {
    /// What an action is called at this point in the hand.
    public func title(for kind: OptionKind) -> String {
        switch kind {
        case .raise: return betsFaced == 0 ? "Open" : "\(betsFaced + 2)-Bet"
        case .call: return betsFaced == 0 ? "Limp" : OptionKind.call.label
        case .allIn, .fold: return kind.label
        }
    }
}

extension ChartLibrary {
    private static let totalCombos = 1326.0

    /// Where the explorer begins: the first seat to act.
    public var firstSpot: SpotKey? {
        Position.preflopSequence.lazy.map { SpotKey(line: [], hero: $0) }.first { spot($0) != nil }
    }

    /// The same line from every seat that has a decision on it, in acting order.
    public func siblings(of key: SpotKey) -> [SpotKey] {
        Position.preflopSequence
            .map { SpotKey(line: key.line, hero: $0) }
            .filter { spot($0) != nil }
    }

    /// The next or previous seat with a decision on this line, wrapping around the table.
    public func neighbour(of key: SpotKey, by offset: Int) -> SpotKey? {
        let seats = siblings(of: key)
        guard seats.count > 1, let index = seats.firstIndex(of: key) else { return nil }
        return seats[(index + offset + seats.count) % seats.count]
    }

    /// The same line and hero against every opponent the book covers, in acting order.
    public func opponents(of key: SpotKey) -> [SpotKey] {
        guard let villain = key.villain else { return [] }
        return Position.preflopSequence
            .filter { $0 != key.hero }
            .map { key.swapping(villain, for: $0) }
            .filter { spot($0) != nil }
    }

    /// Where tapping a seat leads: that seat's own decision on this line, or the same
    /// spot against that opponent. Tapping someone who has acted goes back to their turn.
    public func destination(tapping seat: Position, from key: SpotKey) -> SpotKey? {
        guard seat != key.hero else { return nil }

        let sibling = SpotKey(line: key.line, hero: seat)
        if spot(sibling) != nil { return sibling }

        if seat == key.villain {
            return key.decisions.last { $0.spot.hero == seat }?.spot
        }

        guard let villain = key.villain else { return nil }
        let swapped = key.swapping(villain, for: seat)
        return spot(swapped) != nil ? swapped : nil
    }

    public func choices(at key: SpotKey) -> [SpotChoice] {
        guard let spot = spot(key) else { return [] }

        let reached = reachedHands(at: key)
        let total = reached.reduce(0) { $0 + HandGrid.getCombos(for: $1) }

        return spot.options.map { option in
            let combos = reached.reduce(0.0) {
                $0 + HandGrid.getCombos(for: $1) * Double(spot.frequency(of: option.kind, for: $1)) / Double(Spot.fullFrequency)
            }
            return SpotChoice(
                kind: option.kind,
                code: option.code,
                title: key.title(for: option.kind),
                sizeBB: option.sizeBB,
                share: total > 0 ? combos / total : 0,
                destination: destination(of: option.kind, from: key)
            )
        }
    }

    /// The fraction of all starting hands that get as far as this decision.
    public func reachedShare(at key: SpotKey) -> Double {
        reachedHands(at: key).reduce(0) { $0 + HandGrid.getCombos(for: $1) } / Self.totalCombos
    }

    public func lineEntries(to key: SpotKey) -> [LineEntry] {
        key.decisions.map { decision in
            let kind = OptionKind(decision.kind)
            return LineEntry(
                spot: decision.spot,
                kind: kind,
                title: decision.spot.title(for: kind),
                sizeBB: spot(decision.spot)?.options.first { $0.kind == kind }?.sizeBB
            )
        }
    }

    public func tableState(at key: SpotKey) -> TableState {
        var bets: [Position: Double] = [.SB: 0.5, .BB: 1]
        var lastActions: [Position: OptionKind] = [:]

        for entry in lineEntries(to: key) {
            let highest = bets.values.max() ?? 0
            bets[entry.position] = entry.kind == .call ? highest : entry.sizeBB ?? highest
            lastActions[entry.position] = entry.kind
        }

        let inHand = Set(key.playersInHand ?? [])
        let seats = Position.allCases.map { position -> TableSeat in
            let status: SeatStatus
            if position == key.hero {
                status = .toAct
            } else if let action = lastActions[position] {
                status = .acted(action)
            } else {
                status = inHand.contains(position) ? .waiting : .folded
            }
            return TableSeat(position: position, status: status, bet: bets[position] ?? 0)
        }

        return TableState(
            hero: key.hero,
            seats: seats,
            pot: bets.values.reduce(0, +),
            toCall: (bets.values.max() ?? 0) - (bets[key.hero] ?? 0)
        )
    }

    /// The hero's decisions with this hand, ending at the current spot.
    public func journey(of hand: String, to key: SpotKey) -> [HandStep] {
        let earlier = key.decisions.filter { $0.spot.hero == key.hero }.map(\.spot)
        var isStillIn = true

        return (earlier + [key]).map { step in
            let action = isStillIn ? spot(step)?.primaryAction(for: hand) : nil
            if action == .fold || action == nil { isStillIn = false }
            return HandStep(
                spot: step,
                action: action,
                title: step.stageTitle,
                sizeBB: action.flatMap { kind in spot(step)?.options.first { $0.kind == kind }?.sizeBB },
                isCurrent: step == key
            )
        }
    }

    /// The same hand across seats, or across opponents when only one seat acts here.
    public func comparison(of hand: String, at key: SpotKey) -> HandComparison {
        let seats = siblings(of: key)
        if seats.count > 1 {
            return HandComparison(title: "Other seats", entries: seats.map { entry(for: hand, at: $0, seat: $0.hero, current: key) })
        }
        return HandComparison(title: "Other opponents", entries: opponents(of: key).compactMap { spot in
            spot.villain.map { entry(for: hand, at: spot, seat: $0, current: key) }
        })
    }

    private func entry(for hand: String, at key: SpotKey, seat: Position, current: SpotKey) -> HandComparison.Entry {
        HandComparison.Entry(
            spot: key,
            seat: seat,
            action: reach(of: hand, in: key) == .notReached ? nil : spot(key)?.primaryAction(for: hand),
            isCurrent: key == current
        )
    }

    private func reachedHands(at key: SpotKey) -> [String] {
        HandGrid.allHands.filter { reach(of: $0, in: key) != .notReached }
    }

    /// Where an option leads: folding passes to the next seat, and anything else
    /// passes to whoever acts next on the longer line.
    private func destination(of kind: OptionKind, from key: SpotKey) -> SpotKey? {
        guard let action = ActionKind(kind) else {
            return siblings(of: key).first { $0.hero.preflopOrder > key.hero.preflopOrder }
        }

        let line = key.line + [LineStep(key.hero, action)]
        let seats = Position.preflopSequence
        let start = key.hero.preflopOrder + 1
        return (0..<seats.count)
            .map { SpotKey(line: line, hero: seats[(start + $0) % seats.count]) }
            .first { spot($0) != nil }
    }
}

extension ActionKind {
    /// Nil for fold, which never appears on a line.
    public init?(_ kind: OptionKind) {
        switch kind {
        case .raise: self = .raise
        case .call: self = .call
        case .allIn: self = .allIn
        case .fold: return nil
        }
    }
}

extension SpotKey {
    /// This spot against a different opponent.
    func swapping(_ villain: Position, for seat: Position) -> SpotKey {
        SpotKey(line: line.map { $0.position == villain ? LineStep(seat, $0.kind, sizeTag: $0.sizeTag) : $0 }, hero: hero)
    }
}
