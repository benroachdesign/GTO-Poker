import CoreData
import Foundation
import SwiftData
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

    /// A second connection to one file stands in for CloudKit writing in answers from another device.
    private func twoDevices() throws -> (here: SwiftDataAttemptStore, there: SwiftDataAttemptStore, folder: URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let file = folder.appendingPathComponent("log.store")
        return (try SwiftDataAttemptStore(file: file), try SwiftDataAttemptStore(file: file), folder)
    }

    @Test func answersFromAnotherDeviceArePickedUp() throws {
        let (here, there, folder) = try twoDevices()
        defer { try? FileManager.default.removeItem(at: folder) }

        try here.append(attempt("AA", at: 10))
        #expect(try here.attempts().count == 1)

        try there.append(attempt("KK", at: 20))
        #expect(try here.reloadIfChanged())
        #expect(try here.attempts().map(\.hand) == ["AA", "KK"])
    }

    @Test func nothingIsReloadedWhenNothingArrived() throws {
        let (here, _, folder) = try twoDevices()
        defer { try? FileManager.default.removeItem(at: folder) }

        try here.append(attempt("AA", at: 10))
        _ = try here.attempts()
        #expect(try here.reloadIfChanged() == false)

        try here.append(attempt("KK", at: 20))
        #expect(try here.reloadIfChanged() == false)
    }

    @Test func theSameAnswerArrivingFromAnotherDeviceCountsOnce() throws {
        let (here, there, folder) = try twoDevices()
        defer { try? FileManager.default.removeItem(at: folder) }

        let id = UUID()
        try here.append(attempt("AA", at: 10, id: id))
        _ = try here.attempts()

        try there.append(attempt("AA", at: 10, id: id))
        #expect(try here.reloadIfChanged())
        #expect(try here.attempts().count == 1)
        #expect(try here.reloadIfChanged() == false)
    }

    @Test func aStoreThatHasntBeenReadHasNothingToReload() throws {
        let (here, there, folder) = try twoDevices()
        defer { try? FileManager.default.removeItem(at: folder) }

        try there.append(attempt("AA", at: 10))
        #expect(try here.reloadIfChanged() == false)
        #expect(try here.attempts().count == 1)
    }
}

struct CloudKitSchemaTests {
    private func entity() throws -> NSEntityDescription {
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: [AttemptRecord.self]))
        return try #require(model.entities.first)
    }

    @Test func everyFieldHasADefaultOrCanBeEmpty() throws {
        for attribute in try entity().attributesByName.values {
            #expect(attribute.isOptional || attribute.defaultValue != nil, "\(attribute.name)")
        }
    }

    @Test func thereAreNoUniqueConstraintsOrRelationships() throws {
        let entity = try entity()
        #expect(entity.uniquenessConstraints.isEmpty)
        #expect(entity.relationshipsByName.isEmpty)
    }

    /// Once this has synced, a renamed or removed field would strand data in iCloud.
    /// Adding one is fine: add it here too.
    @Test func existingFieldsKeepTheirNames() throws {
        let names = Set(try entity().attributesByName.keys)
        #expect(names.isSuperset(of: ["id", "book", "spot", "hand", "option", "cell", "answeredAt"]))
    }
}

struct SyncStatusTests {
    private let finishedTransfer = SyncEvent(kind: .transfer, isFinished: true, succeeded: true)
    private let finishedSetup = SyncEvent(kind: .setup, isFinished: true, succeeded: true)
    private let failedSetup = SyncEvent(kind: .setup, isFinished: true, succeeded: false)
    private let failedTransfer = SyncEvent(kind: .transfer, isFinished: true, succeeded: false)

    @Test func aFinishedTransferMeansSynced() {
        #expect(SyncStatus.waiting.applying(finishedTransfer) == .synced)
        #expect(SyncStatus.failed.applying(finishedTransfer) == .synced)
    }

    @Test func workStillInProgressChangesNothing() {
        let running = SyncEvent(kind: .transfer, isFinished: false, succeeded: false)
        #expect(SyncStatus.synced.applying(running) == .synced)
        #expect(SyncStatus.waiting.applying(running) == .waiting)
    }

    @Test func setupAloneDoesntClaimAnythingSynced() {
        #expect(SyncStatus.waiting.applying(finishedSetup) == .waiting)
        #expect(SyncStatus.failed.applying(finishedSetup) == .waiting)
        #expect(SyncStatus.synced.applying(finishedSetup) == .synced)
    }

    @Test func failuresAreReportedRatherThanHidden() {
        #expect(SyncStatus.synced.applying(failedTransfer) == .failed)
        #expect(SyncStatus.waiting.applying(failedSetup) == .failed)
    }

    @Test func noAccountMeansSigningIn() {
        #expect(SyncStatus.waiting.applying(hasAccount: false) == .signedOut)
        #expect(SyncStatus.failed.applying(hasAccount: false) == .signedOut)
    }

    /// Without an account CloudKit also reports a failed setup. Signing in is the useful message.
    @Test func aFailedSetupDoesntHideThatYoureSignedOut() {
        #expect(SyncStatus.signedOut.applying(failedSetup) == .signedOut)
    }

    @Test func signingInStartsWaitingAgain() {
        #expect(SyncStatus.signedOut.applying(hasAccount: true) == .waiting)
    }

    @Test func anAccountChangesNothingElse() {
        #expect(SyncStatus.synced.applying(hasAccount: true) == .synced)
        #expect(SyncStatus.failed.applying(hasAccount: true) == .failed)
    }

    @Test func aDeviceThatIsntSyncingStaysThatWay() {
        #expect(SyncStatus.off.applying(finishedTransfer) == .off)
        #expect(SyncStatus.off.applying(failedTransfer) == .off)
        #expect(SyncStatus.off.applying(hasAccount: false) == .off)
    }

    @MainActor
    @Test func aLocalStoreReportsThatItIsLocal() {
        let monitor = SyncMonitor()
        monitor.attach(to: InMemoryAttemptStore()) {}
        #expect(monitor.status == .off)
    }

    @MainActor
    @Test func anEarlyFailureIsntLostBeforeTheStoreIsAttached() {
        let monitor = SyncMonitor()
        monitor.handle(failedSetup)
        #expect(monitor.status == .failed)
    }
}
