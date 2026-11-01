import Foundation

public enum ActionKind: String, CaseIterable, Sendable {
    case raise = "r"
    case call = "c"
    case allIn = "a"
}

/// One voluntary action in a hand. Folds are implied by whoever the line skips.
public struct LineStep: Hashable, Sendable {
    public let position: Position
    public let kind: ActionKind
    public let sizeTag: String? // Stays nil unless a node branches on size

    public init(_ position: Position, _ kind: ActionKind, sizeTag: String? = nil) {
        self.position = position
        self.kind = kind
        self.sizeTag = sizeTag
    }

    /// e.g. "LJ:r", or "LJ:r@2.5" for a sized branch
    public var id: String {
        let base = "\(position.rawValue):\(kind.rawValue)"
        if let sizeTag { return "\(base)@\(sizeTag)" }
        return base
    }

    public init?(id: String) {
        let sized = id.split(separator: "@", omittingEmptySubsequences: false)
        guard sized.count <= 2 else { return nil }
        let parts = sized[0].split(separator: ":")
        guard parts.count == 2,
              let position = Position(rawValue: String(parts[0])),
              let kind = ActionKind(rawValue: String(parts[1])) else { return nil }
        self.init(position, kind, sizeTag: sized.count == 2 ? String(sized[1]) : nil)
    }
}

/// Identifies a decision: the voluntary actions so far, and who acts next.
/// Written as "line|hero", e.g. "LJ:r,BTN:r|LJ". Opens have an empty line: "|LJ".
/// These ids are stored against drill history, so they must never change.
public struct SpotKey: Hashable, Sendable, Identifiable {
    public let line: [LineStep]
    public let hero: Position

    public init(line: [LineStep], hero: Position) {
        self.line = line
        self.hero = hero
    }

    public var id: String {
        "\(line.map(\.id).joined(separator: ","))|\(hero.rawValue)"
    }

    public init?(id: String) {
        let parts = id.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 2, let hero = Position(rawValue: String(parts[1])) else { return nil }

        var line: [LineStep] = []
        if !parts[0].isEmpty {
            for step in parts[0].split(separator: ",", omittingEmptySubsequences: false) {
                guard let parsed = LineStep(id: String(step)) else { return nil }
                line.append(parsed)
            }
        }
        self.init(line: line, hero: hero)
    }

    /// The heads-up line a chart scenario describes. A 5-bet is all-in at 100bb.
    public init?(scenario: ScenarioType, hero: Position, villain: Position?) {
        switch (scenario, villain) {
        case (.rfi, nil):
            self.init(line: [], hero: hero)
        case (.vsRaise, let villain?):
            self.init(line: [LineStep(villain, .raise)], hero: hero)
        case (.vs3bet, let villain?):
            self.init(line: [LineStep(hero, .raise), LineStep(villain, .raise)], hero: hero)
        case (.vs4bet, let villain?):
            self.init(line: [LineStep(villain, .raise), LineStep(hero, .raise), LineStep(villain, .raise)], hero: hero)
        case (.vs5bet, let villain?):
            self.init(line: [LineStep(hero, .raise), LineStep(villain, .raise), LineStep(hero, .raise), LineStep(villain, .allIn)], hero: hero)
        default:
            return nil
        }
    }

    /// Each earlier decision on the line: the spot that player acted in, and what they did.
    public var decisions: [(spot: SpotKey, kind: ActionKind)] {
        line.indices.map { index in
            (SpotKey(line: Array(line[..<index]), hero: line[index].position), line[index].kind)
        }
    }

    /// The hero's own most recent decision, if they have acted yet.
    public var heroPreviousDecision: (spot: SpotKey, kind: ActionKind)? {
        decisions.last { $0.spot.hero == hero }
    }

    /// Whoever the hero is up against: the last other player to act on the line.
    public var villain: Position? {
        line.last { $0.position != hero }?.position
    }

    /// How many bets the hero is facing. Zero is an open, one is facing an open.
    public var betsFaced: Int {
        line.filter { $0.kind != .call }.count
    }

    public var stageTitle: String {
        if line.last?.kind == .allIn { return "Facing All-in" }
        return ScenarioType.allCases.indices.contains(betsFaced) ? ScenarioType.allCases[betsFaced].label : "Facing \(betsFaced + 1)-Bet"
    }

    /// The stage in words, naming the opponent: "Facing BTN's 3-bet".
    public var situation: String {
        guard let villain else { return ScenarioType.rfi.label }
        let bet = line.last?.kind == .allIn ? "all-in" : betsFaced == 1 ? "open" : "\(betsFaced + 1)-bet"
        return "Facing \(villain.rawValue)'s \(bet)"
    }

    public var isPlayable: Bool {
        playersInHand != nil
    }

    /// Replays the line in table order, folding anyone it skips. Returns who is still
    /// in the hand when the hero acts, or nil if the line couldn't really happen.
    public var playersInHand: [Position]? {
        var players = Position.preflopSequence
        var next = 0
        var lastAggressor: Position? = nil

        func advance(to position: Position) -> Bool {
            while players[next] != position {
                if players[next] == lastAggressor { return false } // Action is closed
                players.remove(at: next)
                if players.isEmpty { return false }
                if next == players.count { next = 0 }
            }
            return players[next] != lastAggressor
        }

        for step in line {
            guard advance(to: step.position) else { return nil }
            if step.kind != .call { lastAggressor = step.position }
            next = (next + 1) % players.count
        }

        guard advance(to: hero), players.count > 1 else { return nil }
        return players
    }
}
