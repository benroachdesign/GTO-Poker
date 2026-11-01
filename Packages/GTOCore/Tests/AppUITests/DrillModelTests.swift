import Foundation
import Testing
import ChartData
import PokerDomain
import Trainer
import TrainerStore
@testable import AppUI

/// A repeatable generator, so a session deals the same hands every run.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@MainActor
struct DrillModelTests {
    private let library: ChartLibrary
    private let store = InMemoryAttemptStore()

    init() throws {
        library = try ChartLibrary.bundled()
    }

    private func model(length: Int = 3) -> DrillModel {
        let model = DrillModel(library: library, store: store, generator: SeededGenerator(state: 42))
        model.length = length
        return model
    }

    /// The right answer to the current question.
    private func bestCode(_ model: DrillModel) throws -> String {
        let question = try #require(model.question)
        let spot = try #require(library.spot(question.spot))
        return spot.primaryAction(for: question.hand).code
    }

    /// A wrong answer to the current question.
    private func wrongCode(_ model: DrillModel) throws -> String {
        let best = try bestCode(model)
        return try #require(model.choices.first { $0.code != best }).code
    }

    @Test func aSessionBeginsWithTheGridFaceDown() throws {
        let model = model()
        model.start()

        let question = try #require(model.question)
        #expect(model.currentAnswer == nil)
        #expect(model.concealedCells[question.hand] == .concealed)
        #expect(!model.concealedCells.values.contains { if case .action = $0 { true } else { false } })
    }

    @Test func handsFoldedEarlierStayVisibleWhileTheRestIsHidden() throws {
        let model = model()
        model.scope = DrillScope(stages: [.facing3Bet])
        model.start()
        #expect(model.concealedCells.values.contains(.unreached))
        #expect(model.concealedCells.values.contains(.concealed))
    }

    @Test func answeringRevealsTheRange() throws {
        let model = model()
        model.start()
        let question = try #require(model.question)
        let spot = try #require(library.spot(question.spot))

        #expect(model.answer(code: try bestCode(model)))
        #expect(model.revealedCells[question.hand] == .action(spot.primaryAction(for: question.hand)))
    }

    @Test func aRightAnswerIsGradedCorrect() throws {
        let model = model()
        model.start()
        model.answer(code: try bestCode(model))
        #expect(model.currentAnswer?.grade == .correct)
    }

    @Test func aWrongAnswerNamesTheBestPlay() throws {
        let model = model()
        model.start()
        let best = try bestCode(model)
        model.answer(code: try wrongCode(model))

        #expect(model.currentAnswer?.grade == .mistake)
        #expect(model.currentAnswer?.best?.code == best)
        #expect(model.misses.count == 1)
    }

    @Test func aQuestionCanOnlyBeAnsweredOnce() throws {
        let model = model()
        model.start()
        let code = try bestCode(model)
        #expect(model.answer(code: code))
        #expect(model.answer(code: code) == false)
        #expect(model.answers.count == 1)
    }

    @Test func keysThatArentOptionsDontCount() throws {
        let model = model()
        model.start()
        #expect(model.answer(code: "x") == false)
        #expect(model.answer(code: "\r") == false)
        #expect(model.currentAnswer == nil)
    }

    @Test func aSessionEndsInASummaryWithTheScore() throws {
        let model = model(length: 3)
        model.start()

        model.answer(code: try bestCode(model))
        model.next()
        model.answer(code: try wrongCode(model))
        model.next()
        model.answer(code: try bestCode(model))
        #expect(model.questionNumber == 3)
        model.next()

        guard case .summary = model.phase else {
            Issue.record("Expected the summary")
            return
        }
        #expect(model.correctCount == 2)
        #expect(model.misses.count == 1)
    }

    @Test func nextDoesNothingUntilAnswered() throws {
        let model = model()
        model.start()
        let question = model.question
        model.next()
        #expect(model.question == question)
    }

    @Test func everyAnswerIsWrittenToTheLog() throws {
        let model = model()
        model.start()
        let question = try #require(model.question)
        let spot = try #require(library.spot(question.spot))
        let code = try bestCode(model)
        model.answer(code: code)

        let attempt = try #require(try store.attempts().first)
        #expect(attempt.book == "6max-100")
        #expect(attempt.spot == question.spot.id)
        #expect(attempt.hand == question.hand)
        #expect(attempt.option == code)
        #expect(attempt.cell == spot.cellSignature(for: question.hand))
    }

    @Test func historyCarriesOverBetweenSessions() throws {
        let first = model()
        first.start()
        first.answer(code: try bestCode(first))
        first.end()
        first.finish()
        #expect(first.historyTotals == SpotRecord(attempts: 1, correct: 1))

        let reopened = model()
        #expect(reopened.historyTotals == SpotRecord(attempts: 1, correct: 1))
    }

    @Test func endingBeforeAnsweringGoesBackToSetup() throws {
        let model = model()
        model.start()
        model.end()
        guard case .setup = model.phase else {
            Issue.record("Expected setup")
            return
        }
    }

    @Test func endingPartWayShowsTheScoreSoFar() throws {
        let model = model(length: 10)
        model.start()
        model.answer(code: try bestCode(model))
        model.next()
        model.end()
        guard case .summary = model.phase else {
            Issue.record("Expected the summary")
            return
        }
        #expect(model.answers.count == 1)
    }

    @Test func aScopeWithNoSpotsCantStart() {
        let model = model()
        model.scope = DrillScope(seats: [.BB], stages: [.open])
        #expect(model.matchingSpotCount == 0)
        #expect(model.canStart == false)
        model.start()
        #expect(model.question == nil)
    }

    @Test func scopesCountTheirSpots() {
        let model = model()
        #expect(model.matchingSpotCount == 65)
        model.scope = DrillScope(stages: [.open])
        #expect(model.matchingSpotCount == 5)
    }

    @Test func drillsAreLockedWhileARulingIsOpen() throws {
        var book = library.book
        book.disputes[0].status = .open
        let model = DrillModel(library: try ChartLibrary(book: book), store: store)

        #expect(model.isLocked)
        #expect(model.canStart == false)
        model.start()
        #expect(model.question == nil)
    }

    @Test func answersShowBetSizesInPlainWords() throws {
        let choices = library.choices(at: try #require(SpotKey(id: "LJ:r|BTN")))
        #expect(choices.first { $0.kind == .raise }?.displayName == "3-Bet 10.5bb")
        #expect(choices.first { $0.kind == .fold }?.displayName == "Fold")
    }
}
