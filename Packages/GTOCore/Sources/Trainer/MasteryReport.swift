import Foundation
import ChartData
import PokerDomain

public struct MasteryGroup: Identifiable, Hashable, Sendable {
    public let title: String
    public let mastery: Double
    public let record: SpotRecord

    public var id: String { title }
}

public struct WeakSpot: Identifiable, Hashable, Sendable {
    public let key: SpotKey
    public let record: SpotRecord

    public var id: String { key.id }
}

/// Everything the Progress screen shows, worked out from the attempt log.
/// Mastery uses the same weights as dealing, so hands at the edge of a range count
/// most and knowing that 72o folds counts for almost nothing.
public struct MasteryReport: Sendable {
    private static let weakSpotLimit = 5
    private static let weakSpotMinimumAttempts = 5 // Fewer than this is mostly noise

    public let overall: Double
    public let record: SpotRecord
    public let dueCount: Int
    public let stages: [MasteryGroup]
    public let seats: [MasteryGroup]
    public let weakest: [WeakSpot]

    public var hasHistory: Bool { record.attempts > 0 }

    public init(attempts: [Attempt], library: ChartLibrary, now: Date, calendar: Calendar = .current) {
        let schedule = ReviewSchedule(attempts: attempts, library: library, calendar: calendar)
        let records = AttemptLog.records(for: attempts, in: library)

        var total = Tally()
        var stageTallies: [DrillStage: Tally] = [:]
        var seatTallies: [Position: Tally] = [:]

        for spot in library.book.spots {
            guard let key = spot.key, let stage = DrillStage(key) else { continue }

            var tally = Tally()
            for (hand, weight) in HandWeights.compute(for: spot, at: key, in: library) {
                tally.add(weight: weight, box: schedule.item(spot: spot.id, hand: hand)?.box ?? 0)
            }
            tally.add(records[spot.id])

            total.merge(tally)
            stageTallies[stage, default: Tally()].merge(tally)
            seatTallies[key.hero, default: Tally()].merge(tally)
        }

        overall = total.mastery
        record = total.record
        dueCount = schedule.due(at: now).count
        stages = DrillStage.allCases.compactMap { stage in
            stageTallies[stage].map { MasteryGroup(title: stage.title, mastery: $0.mastery, record: $0.record) }
        }
        seats = Position.preflopSequence.compactMap { seat in
            seatTallies[seat].map { MasteryGroup(title: seat.rawValue, mastery: $0.mastery, record: $0.record) }
        }
        weakest = records
            .filter { $0.value.attempts >= Self.weakSpotMinimumAttempts && $0.value.accuracy < 1 }
            .compactMap { id, record in SpotKey(id: id).map { WeakSpot(key: $0, record: record) } }
            .sorted { ($0.record.accuracy, -$0.record.attempts, $0.id) < ($1.record.accuracy, -$1.record.attempts, $1.id) }
            .prefix(Self.weakSpotLimit)
            .map { $0 }
    }

    private struct Tally {
        var weighted = 0.0
        var weight = 0.0
        var record = SpotRecord()

        var mastery: Double {
            weight > 0 ? weighted / weight : 0
        }

        mutating func add(weight: Double, box: Int) {
            weighted += weight * Double(box) / Double(ReviewSchedule.topBox)
            self.weight += weight
        }

        mutating func add(_ other: SpotRecord?) {
            guard let other else { return }
            record.attempts += other.attempts
            record.correct += other.correct
        }

        mutating func merge(_ other: Tally) {
            weighted += other.weighted
            weight += other.weight
            add(other.record)
        }
    }
}
