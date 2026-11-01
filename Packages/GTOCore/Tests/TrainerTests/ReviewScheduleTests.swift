import Foundation
import Testing
import ChartData
import PokerDomain
@testable import Trainer

/// Shared by the tests below: a fixed calendar and a builder for answer logs.
private struct Log {
    let library: ChartLibrary
    let calendar: Calendar
    let start: Date

    init() throws {
        library = try ChartLibrary.bundled()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        self.calendar = calendar
        start = Date(timeIntervalSince1970: 1_800_000_000) // A morning, partway through a day
    }

    func day(_ offset: Double) -> Date {
        start.addingTimeInterval(offset * 86_400)
    }

    func answer(_ spotID: String = "|LJ", _ hand: String = "K5s", right: Bool = true, on date: Date) throws -> Attempt {
        let spot = try #require(library.spot(id: spotID))
        let best = spot.primaryAction(for: hand).code
        let wrong = try #require(spot.options.first { $0.code != best }).code
        return Attempt(
            book: library.book.book.id,
            spot: spotID,
            hand: hand,
            option: right ? best : wrong,
            cell: spot.cellSignature(for: hand),
            answeredAt: date
        )
    }

    func schedule(_ attempts: [Attempt]) -> ReviewSchedule {
        ReviewSchedule(attempts: attempts, library: library, calendar: calendar)
    }

    func box(_ attempts: [Attempt]) -> Int? {
        schedule(attempts).item(spot: "|LJ", hand: "K5s")?.box
    }

    func report(_ attempts: [Attempt], at date: Date? = nil) -> MasteryReport {
        MasteryReport(attempts: attempts, library: library, now: date ?? start, calendar: calendar)
    }
}

struct ReviewScheduleTests {
    private let log: Log

    init() throws {
        log = try Log()
    }

    @Test func aFirstRightAnswerComesBackTomorrow() throws {
        let attempts = [try log.answer(on: log.day(0))]
        let item = try #require(log.schedule(attempts).item(spot: "|LJ", hand: "K5s"))

        #expect(item.box == 1)
        #expect(item.dueAt == log.calendar.startOfDay(for: log.day(1)))
    }

    @Test func aHandSeenLateAtNightIsDueNextMorning() throws {
        let midnight = log.calendar.startOfDay(for: log.day(0))
        let lateAtNight = midnight.addingTimeInterval(23.5 * 3_600)
        let item = try #require(log.schedule([try log.answer(on: lateAtNight)]).item(spot: "|LJ", hand: "K5s"))
        #expect(item.dueAt == log.calendar.startOfDay(for: log.day(1)))
    }

    @Test func aHandClimbsEveryBoxWhenAnsweredOnSchedule() throws {
        var attempts: [Attempt] = []
        var day = 0.0
        var boxes: [Int] = []

        for wait in [0.0, 1, 3, 7, 21, 60] {
            day += wait
            attempts.append(try log.answer(on: log.day(day)))
            boxes.append(try #require(log.box(attempts)))
        }
        #expect(boxes == [1, 2, 3, 4, 5, 5])
    }

    @Test func answeringAgainBeforeItsDueProvesNothing() throws {
        let attempts = [
            try log.answer(on: log.day(0)),
            try log.answer(on: log.day(0.01)),
            try log.answer(on: log.day(0.02))
        ]
        #expect(log.box(attempts) == 1)
    }

    @Test func aMistakeDropsTwoBoxes() throws {
        var attempts = [
            try log.answer(on: log.day(0)),
            try log.answer(on: log.day(1)),
            try log.answer(on: log.day(4)),
            try log.answer(on: log.day(11))
        ]
        #expect(log.box(attempts) == 4)

        attempts.append(try log.answer(right: false, on: log.day(32)))
        #expect(log.box(attempts) == 2)
    }

    @Test func aMistakeCountsEvenBeforeItsDue() throws {
        let attempts = [
            try log.answer(on: log.day(0)),
            try log.answer(on: log.day(1)),
            try log.answer(right: false, on: log.day(1.5))
        ]
        #expect(log.box(attempts) == 0)
    }

    @Test func boxesNeverGoBelowTheFirst() throws {
        #expect(log.box([try log.answer(right: false, on: log.day(0))]) == 0)
    }

    @Test func aMistakeComesBackStraightAway() throws {
        let date = log.day(0)
        let schedule = log.schedule([try log.answer(right: false, on: date)])
        #expect(schedule.due(at: date).map(\.hand) == ["K5s"])
    }

    @Test func handsAreOnlyDueOnceTheirTimeComes() throws {
        let schedule = log.schedule([try log.answer(on: log.day(0))])
        #expect(schedule.due(at: log.day(0.2)).isEmpty)
        #expect(schedule.due(at: log.day(1)).count == 1)
    }

    @Test func dueHandsComeLeastKnownFirst() throws {
        let attempts = [
            try log.answer("|LJ", "K5s", on: log.day(0)),
            try log.answer("|LJ", "K5s", on: log.day(1)),
            try log.answer("|LJ", "Q9s", right: false, on: log.day(2)),
            try log.answer("|LJ", "T9s", on: log.day(2))
        ]
        #expect(log.schedule(attempts).due(at: log.day(10)).map(\.hand) == ["Q9s", "T9s", "K5s"])
    }

    @Test func attemptsAreReplayedInTimeOrderHoweverTheyArrive() throws {
        let inOrder = [try log.answer(on: log.day(0)), try log.answer(right: false, on: log.day(1))]
        #expect(log.box(inOrder) == log.box(inOrder.reversed()))
    }

    @Test func aRepairedHandStartsAgainOnItsOwn() throws {
        let kept = try log.answer("|LJ", "AA", on: log.day(0))
        let repaired = Attempt(
            book: log.library.book.book.id,
            spot: "|LJ",
            hand: "K4s",
            option: "R",
            cell: "R:10000", // K4s folds in the current chart, so this was graded against an older one
            answeredAt: log.day(0)
        )
        let schedule = log.schedule([kept, repaired])
        #expect(schedule.seenCount == 1)
        #expect(schedule.item(spot: "|LJ", hand: "AA") != nil)
        #expect(schedule.item(spot: "|LJ", hand: "K4s") == nil)
    }

    @Test func anAcceptableAnswerKeepsItsBox() throws {
        var book = log.library.book
        let index = try #require(book.spots.firstIndex { $0.id == "|LJ" })
        let cell = try #require(HandGrid.coordinates(of: "K5s"))
        var row = Array(book.spots[index].grid[cell.row]).map(String.init)
        row[cell.col] = Spot.mixedCell
        book.spots[index].grid[cell.row] = row.joined()
        book.spots[index].mix = ["K5s": ["R": 8_000, "F": 2_000]]

        let library = try ChartLibrary(book: book)
        let spot = try #require(library.spot(id: "|LJ"))
        let attempts = [("R", 0.0), ("F", 1.0)].map { option, day in
            Attempt(book: book.book.id, spot: "|LJ", hand: "K5s", option: option, cell: spot.cellSignature(for: "K5s"), answeredAt: log.day(day))
        }
        let schedule = ReviewSchedule(attempts: attempts, library: library, calendar: log.calendar)
        #expect(schedule.item(spot: "|LJ", hand: "K5s")?.box == 1)
    }
}

struct MasteryReportTests {
    private let log: Log

    init() throws {
        log = try Log()
    }

    /// Takes one hand to the top box.
    private func mastered(_ spot: String, _ hand: String) throws -> [Attempt] {
        var attempts: [Attempt] = []
        var day = 0.0
        for wait in [0.0, 1, 3, 7, 21] {
            day += wait
            attempts.append(try log.answer(spot, hand, on: log.day(day)))
        }
        return attempts
    }

    @Test func noHistoryMeansNoMastery() {
        let report = log.report([])
        #expect(report.overall == 0)
        #expect(report.hasHistory == false)
        #expect(report.dueCount == 0)
        #expect(report.weakest.isEmpty)
    }

    @Test func thereIsAGroupForEveryStageAndSeat() {
        let report = log.report([])
        #expect(report.stages.map(\.title) == ["Open", "vs Open", "vs 3-Bet", "vs 4-Bet", "vs All-in"])
        #expect(report.seats.map(\.title) == ["LJ", "HJ", "CO", "BTN", "SB", "BB"])
    }

    @Test func masteryRisesAsHandsClimb() throws {
        let one = log.report(try mastered("|LJ", "K5s"))
        let two = log.report(try mastered("|LJ", "K5s") + mastered("|LJ", "K4s"))
        #expect(one.overall > 0)
        #expect(two.overall > one.overall)
    }

    @Test func hardHandsCountForMoreThanObviousOnes() throws {
        let edge = log.report(try mastered("|LJ", "K4s"))
        let obvious = log.report(try mastered("|LJ", "72o"))
        #expect(edge.overall > obvious.overall * 10)
    }

    @Test func masteryLandsInTheRightGroups() throws {
        let report = log.report(try mastered("|LJ", "K5s"))
        #expect(report.stages.first { $0.title == "Open" }?.mastery ?? 0 > 0)
        #expect(report.stages.first { $0.title == "vs Open" }?.mastery == 0)
        #expect(report.seats.first { $0.title == "LJ" }?.mastery ?? 0 > 0)
        #expect(report.seats.first { $0.title == "HJ" }?.mastery == 0)
    }

    @Test func groupsCountAnswersAndAccuracy() throws {
        let attempts = [
            try log.answer("|LJ", "AA", on: log.day(0)),
            try log.answer("|LJ", "KK", right: false, on: log.day(0)),
            try log.answer("LJ:r|HJ", "AA", on: log.day(0))
        ]
        let report = log.report(attempts)
        #expect(report.record == SpotRecord(attempts: 3, correct: 2))
        #expect(report.stages.first { $0.title == "Open" }?.record == SpotRecord(attempts: 2, correct: 1))
        #expect(report.seats.first { $0.title == "HJ" }?.record == SpotRecord(attempts: 1, correct: 1))
    }

    @Test func dueCountsWhatsDueNow() throws {
        let attempts = [
            try log.answer("|LJ", "AA", right: false, on: log.day(0)),
            try log.answer("|LJ", "KK", on: log.day(0))
        ]
        #expect(log.report(attempts).dueCount == 1)
        #expect(log.report(attempts, at: log.day(2)).dueCount == 2)
    }

    @Test func weakestSpotsNeedEnoughAnswersToMeanAnything() throws {
        let attempts = try ["AA", "KK", "QQ", "JJ"].map {
            try log.answer("|LJ", $0, right: false, on: log.day(0))
        }
        #expect(log.report(attempts).weakest.isEmpty)
    }

    @Test func weakestSpotsComeWorstFirstAndLeaveOutPerfectOnes() throws {
        var attempts: [Attempt] = []
        for hand in ["AA", "KK", "QQ", "JJ", "TT"] {
            attempts.append(try log.answer("|LJ", hand, right: hand == "AA", on: log.day(0)))
            attempts.append(try log.answer("|HJ", hand, on: log.day(0)))
            attempts.append(try log.answer("|CO", hand, right: hand != "AA", on: log.day(0)))
        }
        #expect(log.report(attempts).weakest.map(\.key.id) == ["|LJ", "|CO"])
    }
}
