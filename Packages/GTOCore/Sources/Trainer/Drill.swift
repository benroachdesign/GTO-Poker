import Foundation
import ChartData
import PokerDomain

/// How far into the betting a spot is.
public enum DrillStage: Int, CaseIterable, Hashable, Sendable {
    case open, facingOpen, facing3Bet, facing4Bet, facing5Bet

    public init?(_ key: SpotKey) {
        self.init(rawValue: key.betsFaced)
    }

    public var title: String {
        switch self {
        case .open: return "Open"
        case .facingOpen: return "vs Open"
        case .facing3Bet: return "vs 3-Bet"
        case .facing4Bet: return "vs 4-Bet"
        case .facing5Bet: return "vs All-in"
        }
    }

    /// Late stages have so few hands that drilling them often only teaches the pattern of the question.
    var dealWeight: Double {
        switch self {
        case .open, .facingOpen, .facing3Bet: return 1
        case .facing4Bet: return 0.6
        case .facing5Bet: return 0.25
        }
    }
}

public enum DrillFocus: String, CaseIterable, Hashable, Sendable {
    case everything, weakest
}

/// Which spots a session draws from. An empty set means no limit.
public struct DrillScope: Hashable, Sendable {
    public var seats: Set<Position> = []
    public var stages: Set<DrillStage> = []
    public var focus = DrillFocus.everything

    public init(seats: Set<Position> = [], stages: Set<DrillStage> = [], focus: DrillFocus = .everything) {
        self.seats = seats
        self.stages = stages
        self.focus = focus
    }

    public func includes(_ key: SpotKey) -> Bool {
        guard let stage = DrillStage(key) else { return false }
        return (seats.isEmpty || seats.contains(key.hero)) && (stages.isEmpty || stages.contains(stage))
    }
}

public struct DrillQuestion: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let spot: SpotKey
    public let hand: String

    public init(id: UUID = UUID(), spot: SpotKey, hand: String) {
        self.id = id
        self.spot = spot
        self.hand = hand
    }
}

public enum DrillGrade: String, Hashable, Sendable {
    case correct    // The best play, or close to it in a mixed spot
    case acceptable // A real part of the strategy, though not the main line
    case mistake
}

public enum DrillGrader {
    private static let bestShare = 0.5     // Of the top option's frequency
    private static let acceptableFloor = 500 // 5%, in basis points

    /// Grades by how often the strategy takes the chosen option. On pure charts
    /// this is simply right or wrong.
    public static func grade(code: String, hand: String, in spot: Spot) -> DrillGrade {
        let strategy = spot.strategy(for: hand)
        let chosen = strategy[code] ?? 0
        let top = strategy.values.max() ?? 0

        if chosen > 0, Double(chosen) >= Double(top) * bestShare { return .correct }
        return chosen >= acceptableFloor ? .acceptable : .mistake
    }
}

extension Spot {
    /// A hand's strategy as stable text. Stored with each attempt, so that when a
    /// chart is repaired later, history is discarded only for the cells that changed.
    public func cellSignature(for hand: String) -> String {
        strategy(for: hand)
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ",")
    }
}

/// Deals questions from a scope. Hands sit in the pool by how much there is to
/// learn from them, so obvious folds come up rarely and range edges come up often.
public struct DrillDealer: Sendable {
    private struct Pool: Sendable {
        let key: SpotKey
        let weight: Double
        let hands: [String]
        let handWeights: [Double]
    }

    private static let recentLimit = 12
    private static let unseenFocusWeight = 0.4
    private static let minimumFocusWeight = 0.05

    private let pools: [Pool]

    public init(library: ChartLibrary, scope: DrillScope, records: [String: SpotRecord] = [:]) {
        pools = library.book.spots.compactMap { spot in
            guard let key = spot.key, scope.includes(key), let stage = DrillStage(key) else { return nil }

            let weights = HandWeights.compute(for: spot, at: key, in: library)
            guard !weights.isEmpty else { return nil }

            var weight = stage.dealWeight
            if scope.focus == .weakest {
                weight *= Self.focusWeight(records[spot.id])
            }
            return Pool(key: key, weight: weight, hands: weights.map(\.hand), handWeights: weights.map(\.weight))
        }
    }

    public var spotCount: Int { pools.count }

    /// Deals the next question, steering away from recent ones while there are other choices.
    public func deal(after recent: [DrillQuestion] = [], using generator: inout some RandomNumberGenerator) -> DrillQuestion? {
        guard !pools.isEmpty else { return nil }

        let avoid = Set(recent.suffix(Self.recentLimit).map { "\($0.spot.id)#\($0.hand)" })
        var fallback: DrillQuestion?

        for _ in 0..<32 {
            let pool = pools[Self.pick(weights: pools.map(\.weight), using: &generator)]
            let hand = pool.hands[Self.pick(weights: pool.handWeights, using: &generator)]
            let question = DrillQuestion(spot: pool.key, hand: hand)

            if !avoid.contains("\(pool.key.id)#\(hand)"), hand != recent.last?.hand {
                return question
            }
            fallback = fallback ?? question
        }
        return fallback
    }

    private static func focusWeight(_ record: SpotRecord?) -> Double {
        guard let record, record.attempts > 0 else { return unseenFocusWeight }
        return max(1 - record.accuracy, minimumFocusWeight)
    }

    private static func pick(weights: [Double], using generator: inout some RandomNumberGenerator) -> Int {
        let total = weights.reduce(0, +)
        var remaining = Double.random(in: 0..<total, using: &generator)

        for (index, weight) in weights.enumerated() {
            remaining -= weight
            if remaining < 0 { return index }
        }
        return weights.count - 1
    }
}

/// How much a hand is worth drilling at one spot.
enum HandWeights {
    private static let floor = 0.05
    private static let firstRing = 1.0
    private static let secondRing = 0.25

    /// Only hands that really reach the spot are included.
    static func compute(for spot: Spot, at key: SpotKey, in library: ChartLibrary) -> [(hand: String, weight: Double)] {
        var actions = [[OptionKind?]](repeating: [OptionKind?](repeating: nil, count: 13), count: 13)
        for row in 0..<13 {
            for col in 0..<13 {
                let hand = HandGrid.getHandName(row: row, col: col)
                if library.reach(of: hand, in: key) == .reached {
                    actions[row][col] = spot.primaryAction(for: hand)
                }
            }
        }

        var weights: [(hand: String, weight: Double)] = []
        for row in 0..<13 {
            for col in 0..<13 {
                guard let action = actions[row][col] else { continue }

                let hand = HandGrid.getHandName(row: row, col: col)
                let mixedness = 1 - Double(spot.strategy(for: hand).values.max() ?? 0) / Double(Spot.fullFrequency)
                let boundary = boundaryScore(row: row, col: col, action: action, in: actions)
                weights.append((hand, max(mixedness, boundary, floor)))
            }
        }
        return weights
    }

    /// How close a hand sits to one that plays differently. Neighbours are the cells
    /// beside it, plus its suited or offsuit twin, which is the hand it's most often confused with.
    private static func boundaryScore(row: Int, col: Int, action: OptionKind, in actions: [[OptionKind?]]) -> Double {
        let ring = neighbours(row: row, col: col)
        if ring.contains(where: { differs($0, from: action, in: actions) }) { return firstRing }

        let outerRing = ring.flatMap { neighbours(row: $0.row, col: $0.col) }
        return outerRing.contains(where: { differs($0, from: action, in: actions) }) ? secondRing : 0
    }

    private static func differs(_ cell: (row: Int, col: Int), from action: OptionKind, in actions: [[OptionKind?]]) -> Bool {
        guard let other = actions[cell.row][cell.col] else { return false }
        return other != action
    }

    private static func neighbours(row: Int, col: Int) -> [(row: Int, col: Int)] {
        let cells = [(row - 1, col), (row + 1, col), (row, col - 1), (row, col + 1), (col, row)]
        return cells.filter { $0.0 >= 0 && $0.0 < 13 && $0.1 >= 0 && $0.1 < 13 && ($0.0 != row || $0.1 != col) }
    }
}
