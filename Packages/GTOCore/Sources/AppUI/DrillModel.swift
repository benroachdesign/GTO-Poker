import Foundation
import Observation
import os
import ChartData
import PokerDomain
import Trainer
import TrainerStore

struct DrillAnswer: Identifiable {
    let question: DrillQuestion
    let chosen: SpotChoice
    let best: SpotChoice?
    let grade: DrillGrade

    var id: UUID { question.id }
    var isCorrect: Bool { grade == .correct }
}

/// One drill session, from choosing a scope through to the score.
@MainActor
@Observable
final class DrillModel {
    enum Phase {
        case setup, question, answered(DrillAnswer), summary
    }

    static let sessionLengths = [10, 20, 50]
    private static let reviewLimit = 30

    let library: ChartLibrary
    var scope = DrillScope()
    var length = 20

    private(set) var phase = Phase.setup
    private(set) var sessionLength = 0
    private(set) var isReviewing = false
    private(set) var dueCount = 0
    private(set) var question: DrillQuestion?
    private(set) var table: TableState?
    private(set) var choices: [SpotChoice] = []
    private(set) var concealedCells: [String: CellState] = [:]
    private(set) var revealedCells: [String: CellState] = [:]
    private(set) var answers: [DrillAnswer] = []
    private(set) var records: [String: SpotRecord] = [:]
    private(set) var saveFailed = false

    private let store: any AttemptStore
    private let now: () -> Date
    private var generator: any RandomNumberGenerator
    private var dealer: DrillDealer?
    private var reviewQueue: [DrillQuestion] = []
    private var asked: [DrillQuestion] = []
    private var schedule: ReviewSchedule
    private var historyVersion: HistoryVersion?
    private let logger = Logger(subsystem: "com.benroachdesign.GTOPoker", category: "drills")

    init(
        library: ChartLibrary,
        store: any AttemptStore,
        generator: any RandomNumberGenerator = SystemRandomNumberGenerator(),
        now: @escaping () -> Date = Date.init
    ) {
        self.library = library
        self.store = store
        self.generator = generator
        self.now = now
        schedule = ReviewSchedule(attempts: [], library: library)
        refreshHistory()
    }

    /// Drills teach whatever the charts say, so they wait until every ruling is in.
    var isLocked: Bool {
        library.book.openReviewCount > 0
    }

    var matchingSpotCount: Int {
        library.book.spots.filter { $0.key.map(scope.includes) ?? false }.count
    }

    var canStart: Bool {
        !isLocked && matchingSpotCount > 0
    }

    var currentAnswer: DrillAnswer? {
        if case .answered(let answer) = phase { return answer }
        return nil
    }

    var isInSession: Bool {
        switch phase {
        case .question, .answered: return true
        case .setup, .summary: return false
        }
    }

    var correctCount: Int {
        answers.filter(\.isCorrect).count
    }

    var misses: [DrillAnswer] {
        answers.filter { !$0.isCorrect }
    }

    /// The question number on screen, counting from 1.
    var questionNumber: Int {
        currentAnswer == nil ? answers.count + 1 : answers.count
    }

    var historyTotals: SpotRecord {
        records.values.reduce(into: SpotRecord()) {
            $0.attempts += $1.attempts
            $0.correct += $1.correct
        }
    }

    func start() {
        guard canStart else { return }

        refreshHistory()
        dealer = DrillDealer(library: library, scope: scope, records: records)
        isReviewing = false
        sessionLength = length
        beginSession()
    }

    /// A session of whatever spaced review says is due, least known first.
    /// A drill already under way is left alone, so nothing you were doing gets thrown away.
    func startReview() {
        guard !isLocked, !isInSession else { return }

        refreshHistory()
        reviewQueue = schedule.due(at: now())
            .prefix(Self.reviewLimit)
            .compactMap { item in
                SpotKey(id: item.spot).map { DrillQuestion(spot: $0, hand: item.hand) }
            }
        guard !reviewQueue.isEmpty else { return }

        isReviewing = true
        sessionLength = reviewQueue.count
        beginSession()
    }

    /// Goes round again in whichever kind of session just ended.
    func repeatSession() {
        if isReviewing {
            startReview()
        } else {
            start()
        }
    }

    private func beginSession() {
        answers = []
        asked = []
        dealNext()
    }

    /// Answers by option code: R, A, C or F. Returns whether it counted.
    @discardableResult
    func answer(code: String) -> Bool {
        guard case .question = phase, let question, let spot = library.spot(question.spot),
              let chosen = choices.first(where: { $0.code == code.uppercased() }) else {
            return false
        }

        let best = spot.primaryAction(for: question.hand)
        let answer = DrillAnswer(
            question: question,
            chosen: chosen,
            best: choices.first { $0.kind == best },
            grade: DrillGrader.grade(code: chosen.code, hand: question.hand, in: spot)
        )
        answers.append(answer)
        phase = .answered(answer)
        record(chosen, for: question, in: spot)
        return true
    }

    func next() {
        guard case .answered = phase else { return }

        if answers.count >= sessionLength {
            showSummary()
        } else {
            dealNext()
        }
    }

    func end() {
        if answers.isEmpty {
            phase = .setup
        } else {
            showSummary()
        }
    }

    func finish() {
        refreshHistory()
        phase = .setup
    }

    /// Reloads everything worked out from the log, such as how much is due.
    func refreshHistory() {
        do {
            let attempts = try store.attempts()
            let version = HistoryVersion(attempts: attempts, now: now())
            guard version != historyVersion else { return }

            historyVersion = version
            records = AttemptLog.records(for: attempts, in: library)
            schedule = ReviewSchedule(attempts: attempts, library: library)
            dueCount = schedule.due(at: now()).count
        } catch {
            logger.error("Failed to load attempts: \(error)")
        }
    }

    private func showSummary() {
        refreshHistory()
        phase = .summary
    }

    private func dealNext() {
        let dealt = isReviewing ? reviewQueue.popFirst() : dealer?.deal(after: asked, using: &generator)
        guard let dealt else {
            phase = .setup
            return
        }
        asked.append(dealt)
        present(dealt)
    }

    private func present(_ dealt: DrillQuestion) {
        guard let spot = library.spot(dealt.spot) else { return }

        var concealed: [String: CellState] = [:]
        var revealed: [String: CellState] = [:]
        for hand in HandGrid.allHands {
            let isReached = library.reach(of: hand, in: dealt.spot) != .notReached
            concealed[hand] = isReached ? .concealed : .unreached
            revealed[hand] = isReached ? .action(spot.primaryAction(for: hand)) : .unreached
        }

        concealedCells = concealed
        revealedCells = revealed
        table = library.tableState(at: dealt.spot)
        choices = library.choices(at: dealt.spot)
        question = dealt
        phase = .question
    }

    private func record(_ chosen: SpotChoice, for question: DrillQuestion, in spot: Spot) {
        let attempt = Attempt(
            book: library.book.book.id,
            spot: question.spot.id,
            hand: question.hand,
            option: chosen.code,
            cell: spot.cellSignature(for: question.hand),
            answeredAt: now()
        )
        do {
            try store.append(attempt)
        } catch {
            saveFailed = true
            logger.error("Failed to save attempt: \(error)")
        }
    }
}

private extension Array {
    mutating func popFirst() -> Element? {
        isEmpty ? nil : removeFirst()
    }
}
