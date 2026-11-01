import Foundation
import ChartData

/// Where one hand at one spot stands in spaced review.
public struct ReviewItem: Identifiable, Hashable, Sendable {
    public let spot: String
    public let hand: String
    public let box: Int
    public let dueAt: Date

    public var id: String { "\(spot)#\(hand)" }
}

/// Leitner boxes, worked out by replaying the attempt log. A hand climbs a box each
/// time it's answered right once it's due, and falls two on any mistake.
public struct ReviewSchedule: Sendable {
    /// Days until a hand comes back from each box. Box 0 means this session.
    public static let intervals = [0, 1, 3, 7, 21, 60]
    public static var topBox: Int { intervals.count - 1 }
    private static let mistakeDrop = 2

    private let items: [String: ReviewItem]

    public init(attempts: [Attempt], library: ChartLibrary, calendar: Calendar = .current) {
        var items: [String: ReviewItem] = [:]

        let ordered = AttemptLog.valid(attempts, in: library).sorted { $0.answeredAt < $1.answeredAt }
        for attempt in ordered {
            guard let spot = library.spot(id: attempt.spot) else { continue }

            let id = "\(attempt.spot)#\(attempt.hand)"
            let grade = DrillGrader.grade(code: attempt.option, hand: attempt.hand, in: spot)
            let box = Self.nextBox(after: grade, current: items[id], at: attempt.answeredAt)

            items[id] = ReviewItem(
                spot: attempt.spot,
                hand: attempt.hand,
                box: box,
                dueAt: Self.dueDate(for: box, answeredAt: attempt.answeredAt, calendar: calendar)
            )
        }
        self.items = items
    }

    public var seenCount: Int { items.count }

    public func item(spot: String, hand: String) -> ReviewItem? {
        items["\(spot)#\(hand)"]
    }

    /// Hands due now, the least known first, then whichever has waited longest.
    public func due(at date: Date) -> [ReviewItem] {
        items.values
            .filter { $0.dueAt <= date }
            .sorted { ($0.box, $0.dueAt, $0.id) < ($1.box, $1.dueAt, $1.id) }
    }

    private static func nextBox(after grade: DrillGrade, current: ReviewItem?, at date: Date) -> Int {
        let box = current?.box ?? 0

        switch grade {
        case .mistake:
            return max(box - mistakeDrop, 0)
        case .acceptable:
            return box
        case .correct:
            // Answering again before it's due proves nothing new, so it doesn't count
            if let current, date < current.dueAt { return box }
            return min(box + 1, topBox)
        }
    }

    /// Due at the start of a day rather than a set number of hours later, so
    /// a hand studied late at night comes back in the morning, not the next night.
    private static func dueDate(for box: Int, answeredAt: Date, calendar: Calendar) -> Date {
        let days = intervals[box]
        guard days > 0 else { return answeredAt }
        return calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: answeredAt)) ?? answeredAt
    }
}
