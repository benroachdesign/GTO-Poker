import Foundation
import PokerDomain

/// One compiled set of ranges: the file `chartc` writes and the app reads.
/// New fields must be optional, so existing spot ids and drill history stay valid.
public struct RangeBook: Codable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var book: BookInfo
    public var spots: [Spot]
    public var patches: [Patch]
    public var rules: [ActionRule]
    public var disputes: [Dispute]

    public init(schemaVersion: Int = RangeBook.currentSchemaVersion, book: BookInfo, spots: [Spot], patches: [Patch] = [], rules: [ActionRule] = [], disputes: [Dispute] = []) {
        self.schemaVersion = schemaVersion
        self.book = book
        self.spots = spots
        self.patches = patches
        self.rules = rules
        self.disputes = disputes
    }

    /// Repairs and questions still waiting for the chart owner. Drills stay locked until this is zero.
    public var openReviewCount: Int {
        patches.filter { $0.status == .inferred }.count
            + rules.filter { $0.status == .inferred }.count
            + disputes.filter { $0.status == .open }.count
    }
}

public struct BookInfo: Codable, Sendable {
    public var id: String
    public var title: String
    public var format: String
    public var stackBB: Int
    public var source: SourceInfo

    public init(id: String, title: String, format: String, stackBB: Int, source: SourceInfo) {
        self.id = id
        self.title = title
        self.format = format
        self.stackBB = stackBB
        self.source = source
    }
}

public struct SourceInfo: Codable, Sendable {
    public var file: String
    public var sha256: String

    public init(file: String, sha256: String) {
        self.file = file
        self.sha256 = sha256
    }
}

public enum OptionKind: String, Codable, CaseIterable, Sendable {
    case raise, allIn, call, fold

    public init(_ kind: ActionKind) {
        switch kind {
        case .raise: self = .raise
        case .call: self = .call
        case .allIn: self = .allIn
        }
    }

    public init?(code: String) {
        guard let kind = OptionKind.allCases.first(where: { $0.code == code }) else { return nil }
        self = kind
    }

    public var code: String {
        switch self {
        case .raise: return "R"
        case .allIn: return "A"
        case .call: return "C"
        case .fold: return "F"
        }
    }

    public var label: String {
        switch self {
        case .raise: return "Raise"
        case .allIn: return "All-in"
        case .call: return "Call"
        case .fold: return "Fold"
        }
    }
}

public struct SpotOption: Codable, Hashable, Sendable {
    public var code: String
    public var kind: OptionKind
    public var sizeBB: Double?

    public init(code: String, kind: OptionKind, sizeBB: Double? = nil) {
        self.code = code
        self.kind = kind
        self.sizeBB = sizeBB
    }
}

public enum SpotStatus: String, Codable, Sendable {
    case source     // Exactly as the source chart has it
    case inferred   // Repaired, waiting for a ruling
    case confirmed  // Repaired and ruled on
    case disputed   // Has an open question
}

public struct Provenance: Codable, Sendable {
    public var sourceLine: Int?
    public var status: SpotStatus
    public var patches: [String]?
    public var rules: [String]?
    public var disputes: [String]?

    public init(sourceLine: Int?, status: SpotStatus, patches: [String]? = nil, rules: [String]? = nil, disputes: [String]? = nil) {
        self.sourceLine = sourceLine
        self.status = status
        self.patches = patches
        self.rules = rules
        self.disputes = disputes
    }
}

public struct Spot: Codable, Identifiable, Sendable {
    /// Marks a grid cell whose strategy lives in `mix`.
    public static let mixedCell = "*"
    /// Frequencies are basis points: 10,000 is always.
    public static let fullFrequency = 10_000

    public var id: String
    public var options: [SpotOption]
    public var grid: [String] // 13 rows of 13 option codes, laid out like HandGrid
    public var mix: [String: [String: Int]]? // Hand -> option code -> basis points
    public var provenance: Provenance

    public init(id: String, options: [SpotOption], grid: [String], mix: [String: [String: Int]]? = nil, provenance: Provenance) {
        self.id = id
        self.options = options
        self.grid = grid
        self.mix = mix
        self.provenance = provenance
    }

    public var key: SpotKey? { SpotKey(id: id) }

    public func code(for hand: String) -> String? {
        guard let cell = HandGrid.coordinates(of: hand), cell.row < grid.count else { return nil }
        let row = Array(grid[cell.row])
        return cell.col < row.count ? String(row[cell.col]) : nil
    }

    /// Option code -> basis points for a hand.
    public func strategy(for hand: String) -> [String: Int] {
        guard let code = code(for: hand) else { return [:] }
        if code == Spot.mixedCell { return mix?[hand] ?? [:] }
        return [code: Spot.fullFrequency]
    }

    public func frequency(of kind: OptionKind, for hand: String) -> Int {
        let strategy = strategy(for: hand)
        return options.filter { $0.kind == kind }.reduce(0) { $0 + (strategy[$1.code] ?? 0) }
    }

    /// The action a hand takes most often. Ties go to the more aggressive option.
    public func primaryAction(for hand: String) -> OptionKind {
        var best = OptionKind.fold
        var bestFrequency = 0
        for option in options {
            let frequency = frequency(of: option.kind, for: hand)
            if frequency > bestFrequency {
                best = option.kind
                bestFrequency = frequency
            }
        }
        return best
    }
}

public enum PatchStatus: String, Codable, Sendable {
    case inferred   // Awaiting a ruling
    case confirmed
}

public struct CellChange: Codable, Hashable, Sendable {
    public var hand: String
    public var was: String
    public var now: String

    public init(hand: String, was: String, now: String) {
        self.hand = hand
        self.was = was
        self.now = now
    }
}

/// A repair to the source chart, kept in the book so every change stays auditable.
public struct Patch: Codable, Identifiable, Sendable {
    public var id: String
    public var kind: String
    public var spot: String
    public var sourceLine: Int
    public var originalLabel: String
    public var reason: String
    public var evidence: String
    public var decidedBy: String?
    public var status: PatchStatus
    public var changes: [CellChange]

    public init(id: String, kind: String, spot: String, sourceLine: Int, originalLabel: String, reason: String, evidence: String, decidedBy: String?, status: PatchStatus, changes: [CellChange]) {
        self.id = id
        self.kind = kind
        self.spot = spot
        self.sourceLine = sourceLine
        self.originalLabel = originalLabel
        self.reason = reason
        self.evidence = evidence
        self.decidedBy = decidedBy
        self.status = status
        self.changes = changes
    }
}

/// Rewrites one option code across a whole scenario, leaving the source CSV untouched.
public struct ActionRule: Codable, Identifiable, Sendable {
    public var id: String
    public var scenario: String
    public var from: String
    public var to: String
    public var reason: String
    public var evidence: String
    public var decidedBy: String?
    public var status: PatchStatus
}

public enum DisputeStatus: String, Codable, Sendable {
    case open, resolved
}

/// A question only the chart's owner can answer. The data stays as it is until they do.
public struct Dispute: Codable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var question: String
    public var detail: String
    public var spots: [String]
    public var hands: [String]?
    public var ruling: String?
    public var decidedBy: String?
    public var status: DisputeStatus
}
