import Foundation

public enum Position: String, CaseIterable, Sendable {
    case SB, BB, LJ, HJ, CO, BTN

    // Helper to get index 0-5
    public var index: Int {
        switch self {
        case .SB: return 0
        case .BB: return 1
        case .LJ: return 2
        case .HJ: return 3
        case .CO: return 4
        case .BTN: return 5
        }
    }

    public static func fromIndex(_ index: Int) -> Position {
        let normalizedIndex = (index % 6 + 6) % 6
        return allCases[normalizedIndex]
    }

    public static let preflopSequence: [Position] = [.LJ, .HJ, .CO, .BTN, .SB, .BB]

    /// True if this seat acts after the other once the flop comes.
    public func isInPosition(against other: Position) -> Bool {
        index > other.index
    }

    public var preflopOrder: Int {
        switch self {
        case .LJ: return 0
        case .HJ: return 1
        case .CO: return 2
        case .BTN: return 3
        case .SB: return 4
        case .BB: return 5
        }
    }
}

public enum ScenarioType: String, CaseIterable, Sendable {
    case rfi = "Open"
    case vsRaise = "vs Raise"
    case vs3bet = "vs 3bet"
    case vs4bet = "vs 4bet"
    case vs5bet = "vs 5bet"

    public var label: String {
        switch self {
        case .rfi: return "Opening"
        case .vsRaise: return "Facing Open"
        case .vs3bet: return "Facing 3-Bet"
        case .vs4bet: return "Facing 4-Bet"
        case .vs5bet: return "Facing 5-Bet"
        }
    }

    public var badge: String? {
        switch self {
        case .rfi: return nil
        case .vsRaise: return "R"
        case .vs3bet: return "3B"
        case .vs4bet: return "4B"
        case .vs5bet: return "5B"
        }
    }
}
