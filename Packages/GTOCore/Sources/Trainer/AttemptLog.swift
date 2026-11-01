import Foundation
import ChartData

/// One answered question. This append-only log is the only stored truth:
/// everything about progress is worked out from it.
public struct Attempt: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let book: String
    public let spot: String
    public let hand: String
    public let option: String
    public let cell: String // The hand's strategy when it was asked, from `Spot.cellSignature`
    public let answeredAt: Date

    public init(id: UUID = UUID(), book: String, spot: String, hand: String, option: String, cell: String, answeredAt: Date) {
        self.id = id
        self.book = book
        self.spot = spot
        self.hand = hand
        self.option = option
        self.cell = cell
        self.answeredAt = answeredAt
    }
}

public struct SpotRecord: Hashable, Sendable {
    public var attempts = 0
    public var correct = 0

    public init(attempts: Int = 0, correct: Int = 0) {
        self.attempts = attempts
        self.correct = correct
    }

    public var accuracy: Double {
        attempts > 0 ? Double(correct) / Double(attempts) : 0
    }
}

public enum AttemptLog {
    /// Attempts that still mean something against this book. A chart repair
    /// discards only the hands it changed, and everything else carries on.
    public static func valid(_ attempts: [Attempt], in library: ChartLibrary) -> [Attempt] {
        attempts.filter { attempt in
            guard attempt.book == library.book.book.id, let spot = library.spot(id: attempt.spot) else { return false }
            return spot.cellSignature(for: attempt.hand) == attempt.cell
        }
    }

    /// Accuracy per spot, by spot id, regraded against the current book.
    public static func records(for attempts: [Attempt], in library: ChartLibrary) -> [String: SpotRecord] {
        var records: [String: SpotRecord] = [:]

        for attempt in valid(attempts, in: library) {
            guard let spot = library.spot(id: attempt.spot) else { continue }

            let grade = DrillGrader.grade(code: attempt.option, hand: attempt.hand, in: spot)
            records[attempt.spot, default: SpotRecord()].attempts += 1
            if grade != .mistake {
                records[attempt.spot, default: SpotRecord()].correct += 1
            }
        }
        return records
    }
}
