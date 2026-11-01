import Foundation
import Testing
import ChartData
import PokerDomain
@testable import Trainer

/// A repeatable generator, so every run of these tests deals the same hands.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

struct DrillDealerTests {
    private let library: ChartLibrary

    init() throws {
        library = try ChartLibrary.bundled()
    }

    private func deals(_ count: Int, scope: DrillScope = DrillScope(), records: [String: SpotRecord] = [:], seed: UInt64 = 42) -> [DrillQuestion] {
        let dealer = DrillDealer(library: library, scope: scope, records: records)
        var generator = SeededGenerator(seed: seed)
        var questions: [DrillQuestion] = []
        for _ in 0..<count {
            if let question = dealer.deal(after: questions, using: &generator) { questions.append(question) }
        }
        return questions
    }

    @Test func onlyHandsThatReachTheSpotAreEverDealt() {
        for question in deals(10_000) {
            #expect(library.reach(of: question.hand, in: question.spot) == .reached, "\(question.spot.id) \(question.hand)")
        }
    }

    @Test func everySpotInScopeGetsDealt() {
        let dealt = Set(deals(10_000).map(\.spot.id))
        #expect(dealt.count == 65)
    }

    @Test func dealsLeanHeavilyTowardRangeBoundaries() throws {
        let questions = deals(20_000, scope: DrillScope(seats: [.LJ], stages: [.open]))
        let counts = Dictionary(grouping: questions, by: \.hand).mapValues(\.count)

        // K4s folds right beside K5s, which opens. 72o is nowhere near a decision
        let edge = try #require(counts["K4s"])
        let obvious = counts["72o"] ?? 0
        #expect(edge > obvious * 10)
    }

    @Test func hardHandsFarOutnumberObviousOnes() {
        let questions = deals(10_000, scope: DrillScope(seats: [.BTN], stages: [.open]))
        let obviousFolds = questions.filter { ["72o", "83o", "94o", "32o", "42o"].contains($0.hand) }
        #expect(Double(obviousFolds.count) / Double(questions.count) < 0.02)
    }

    @Test func obviousHandsStillComeUpSometimes() {
        let hands = Set(deals(20_000, scope: DrillScope(seats: [.LJ], stages: [.open])).map(\.hand))
        #expect(hands.count == 169)
    }

    @Test func allInSpotsAreDealtLessOften() {
        let questions = deals(10_000)
        let stages = Dictionary(grouping: questions) { DrillStage($0.spot) }.mapValues(\.count)
        #expect((stages[.facing5Bet] ?? 0) * 2 < stages[.facing3Bet] ?? 0)
    }

    @Test func seatScopeLimitsTheSpots() {
        let questions = deals(2_000, scope: DrillScope(seats: [.BB, .SB]))
        #expect(questions.allSatisfy { [.BB, .SB].contains($0.spot.hero) })
    }

    @Test func stageScopeLimitsTheSpots() {
        let questions = deals(2_000, scope: DrillScope(stages: [.facing3Bet]))
        #expect(questions.allSatisfy { $0.spot.betsFaced == 2 })
    }

    @Test func aScopeWithNoSpotsDealsNothing() {
        let dealer = DrillDealer(library: library, scope: DrillScope(seats: [.BB], stages: [.open]))
        var generator = SeededGenerator(seed: 1)
        #expect(dealer.spotCount == 0)
        #expect(dealer.deal(using: &generator) == nil)
    }

    @Test func theSameHandNeverComesUpTwiceInARow() {
        let questions = deals(5_000)
        for (previous, next) in zip(questions, questions.dropFirst()) {
            #expect(previous.hand != next.hand)
        }
    }

    @Test func recentQuestionsAreNotRepeated() {
        let questions = deals(2_000)
        for index in questions.indices.dropFirst(12) {
            let recent = questions[(index - 12)..<index].map { "\($0.spot.id)#\($0.hand)" }
            #expect(!recent.contains("\(questions[index].spot.id)#\(questions[index].hand)"))
        }
    }

    @Test func aTinyPoolStillDeals() {
        let scope = DrillScope(seats: [.LJ], stages: [.facing5Bet])
        #expect(deals(200, scope: scope).count == 200)
    }

    @Test func aSeedDealsTheSameHandsEveryTime() {
        let first = deals(500).map { "\($0.spot.id)#\($0.hand)" }
        let second = deals(500).map { "\($0.spot.id)#\($0.hand)" }
        #expect(first == second)
        #expect(first != deals(500, seed: 7).map { "\($0.spot.id)#\($0.hand)" })
    }

    @Test func weakestFocusDrillsTheSpotsYouMiss() {
        let records = [
            "|LJ": SpotRecord(attempts: 20, correct: 4),
            "|BTN": SpotRecord(attempts: 20, correct: 20)
        ]
        let questions = deals(5_000, scope: DrillScope(stages: [.open], focus: .weakest), records: records)
        let counts = Dictionary(grouping: questions, by: \.spot.id).mapValues(\.count)
        #expect((counts["|LJ"] ?? 0) > (counts["|BTN"] ?? 0) * 5)
    }
}

struct DrillGraderTests {
    private func spot(cell: String = "R", mix: [String: Int]? = nil) -> Spot {
        var grid = Array(repeating: String(repeating: "F", count: 13), count: 13)
        grid[0] = cell + String(repeating: "F", count: 12)
        return Spot(
            id: "|LJ",
            options: [SpotOption(code: "R", kind: .raise), SpotOption(code: "C", kind: .call), SpotOption(code: "F", kind: .fold)],
            grid: grid,
            mix: mix.map { ["AA": $0] },
            provenance: Provenance(sourceLine: nil, status: .source)
        )
    }

    @Test func pureChartsAreSimplyRightOrWrong() {
        #expect(DrillGrader.grade(code: "R", hand: "AA", in: spot()) == .correct)
        #expect(DrillGrader.grade(code: "F", hand: "AA", in: spot()) == .mistake)
        #expect(DrillGrader.grade(code: "C", hand: "AA", in: spot()) == .mistake)
        #expect(DrillGrader.grade(code: "F", hand: "72o", in: spot()) == .correct)
    }

    @Test func theTopOptionInAMixIsCorrect() {
        let mixed = spot(cell: Spot.mixedCell, mix: ["R": 6_000, "C": 3_500, "F": 500])
        #expect(DrillGrader.grade(code: "R", hand: "AA", in: mixed) == .correct)
    }

    @Test func aCloseSecondInAMixCountsAsCorrect() {
        let mixed = spot(cell: Spot.mixedCell, mix: ["R": 5_500, "C": 4_500])
        #expect(DrillGrader.grade(code: "C", hand: "AA", in: mixed) == .correct)
    }

    @Test func aRealButMinorOptionIsAcceptable() {
        let mixed = spot(cell: Spot.mixedCell, mix: ["R": 8_000, "C": 1_500, "F": 500])
        #expect(DrillGrader.grade(code: "C", hand: "AA", in: mixed) == .acceptable)
        #expect(DrillGrader.grade(code: "F", hand: "AA", in: mixed) == .acceptable)
    }

    @Test func aTraceOptionIsAMistake() {
        let mixed = spot(cell: Spot.mixedCell, mix: ["R": 9_800, "F": 200])
        #expect(DrillGrader.grade(code: "F", hand: "AA", in: mixed) == .mistake)
    }

    @Test func signaturesAreStableAcrossKeyOrder() {
        let mixed = spot(cell: Spot.mixedCell, mix: ["R": 6_000, "F": 4_000])
        #expect(mixed.cellSignature(for: "AA") == "F:4000,R:6000")
        #expect(spot().cellSignature(for: "AA") == "R:10000")
    }
}

struct AttemptLogTests {
    private let library: ChartLibrary
    private let book: String

    init() throws {
        library = try ChartLibrary.bundled()
        book = library.book.book.id
    }

    private func attempt(_ spotID: String, _ hand: String, option: String, cell: String? = nil, book: String? = nil) throws -> Attempt {
        let spot = try #require(library.spot(id: spotID))
        return Attempt(
            book: book ?? self.book,
            spot: spotID,
            hand: hand,
            option: option,
            cell: cell ?? spot.cellSignature(for: hand),
            answeredAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test func attemptsAreKeptWhileTheirCellIsUnchanged() throws {
        let log = [try attempt("|LJ", "AA", option: "R"), try attempt("|LJ", "72o", option: "F")]
        #expect(AttemptLog.valid(log, in: library) == log)
    }

    @Test func aRepairDiscardsOnlyTheHandsItChanged() throws {
        let kept = try attempt("|LJ", "AA", option: "R")
        let repaired = try attempt("|LJ", "K4s", option: "R", cell: "R:10000")
        #expect(AttemptLog.valid([kept, repaired], in: library) == [kept])
    }

    @Test func attemptsFromAnotherBookAreIgnored() throws {
        #expect(AttemptLog.valid([try attempt("|LJ", "AA", option: "R", book: "9max")], in: library).isEmpty)
    }

    @Test func attemptsOnASpotThatNoLongerExistsAreIgnored() {
        let gone = Attempt(book: book, spot: "|BB", hand: "AA", option: "R", cell: "R:10000", answeredAt: .distantPast)
        #expect(AttemptLog.valid([gone], in: library).isEmpty)
    }

    @Test func recordsCountAccuracyPerSpot() throws {
        let log = [
            try attempt("|LJ", "AA", option: "R"),
            try attempt("|LJ", "KK", option: "R"),
            try attempt("|LJ", "QQ", option: "F"),
            try attempt("|HJ", "AA", option: "F")
        ]
        let records = AttemptLog.records(for: log, in: library)
        #expect(records["|LJ"] == SpotRecord(attempts: 3, correct: 2))
        #expect(records["|HJ"] == SpotRecord(attempts: 1, correct: 0))
    }

    @Test func discardedAttemptsDontCountTowardRecords() throws {
        let stale = try attempt("|LJ", "K4s", option: "R", cell: "R:10000")
        #expect(AttemptLog.records(for: [stale], in: library).isEmpty)
    }

    @Test func attemptsRoundTripThroughJSON() throws {
        let original = try attempt("|LJ", "AA", option: "R")
        let decoded = try JSONDecoder().decode(Attempt.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }
}
