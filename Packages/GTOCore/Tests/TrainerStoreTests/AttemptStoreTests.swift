import Foundation
import Testing
import Trainer
@testable import TrainerStore

@MainActor
struct AttemptStoreTests {
    private func attempt(_ hand: String, at seconds: TimeInterval, id: UUID = UUID()) -> Attempt {
        Attempt(id: id, book: "6max-100", spot: "|LJ", hand: hand, option: "R", cell: "R:10000", answeredAt: Date(timeIntervalSince1970: seconds))
    }

    @Test func attemptsSurviveTheDatabaseInOrder() throws {
        let store = try SwiftDataAttemptStore(inMemory: true)
        try store.append(attempt("KK", at: 20))
        try store.append(attempt("AA", at: 10))
        #expect(try store.attempts().map(\.hand) == ["AA", "KK"])
    }

    @Test func everyFieldComesBackUnchanged() throws {
        let store = try SwiftDataAttemptStore(inMemory: true)
        let original = attempt("AA", at: 10)
        try store.append(original)
        #expect(try store.attempts() == [original])
    }

    @Test func aDuplicateFromSyncCountsOnce() throws {
        let store = try SwiftDataAttemptStore(inMemory: true)
        let id = UUID()
        try store.append(attempt("AA", at: 10, id: id))
        try store.append(attempt("AA", at: 10, id: id))
        #expect(try store.attempts().count == 1)
    }

    @Test func answersAddedAfterReadingAreStillSeen() throws {
        let store = try SwiftDataAttemptStore(inMemory: true)
        try store.append(attempt("AA", at: 10))
        #expect(try store.attempts().count == 1)

        try store.append(attempt("KK", at: 20))
        #expect(try store.attempts().map(\.hand) == ["AA", "KK"])
    }

    @Test func aDuplicateAfterReadingCountsOnce() throws {
        let store = try SwiftDataAttemptStore(inMemory: true)
        let id = UUID()
        try store.append(attempt("AA", at: 10, id: id))
        _ = try store.attempts()
        try store.append(attempt("AA", at: 10, id: id))
        #expect(try store.attempts().count == 1)
    }

    @Test func historyExportsAsJSON() throws {
        let store = try SwiftDataAttemptStore(inMemory: true)
        try store.append(attempt("AA", at: 10))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exported = try decoder.decode([Attempt].self, from: store.exportJSON())
        #expect(exported == (try store.attempts()))
    }

    @Test func theFallbackStoreKeepsItsLog() throws {
        let store = InMemoryAttemptStore()
        let original = attempt("AA", at: 10)
        try store.append(original)
        #expect(try store.attempts() == [original])
    }
}
