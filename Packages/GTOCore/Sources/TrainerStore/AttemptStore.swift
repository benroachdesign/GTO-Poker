import Foundation
import SwiftData
import Trainer

/// Keeps the attempt log. Attempts are only ever added, never changed.
@MainActor
public protocol AttemptStore: AnyObject {
    func append(_ attempt: Attempt) throws
    func attempts() throws -> [Attempt]
}

extension AttemptStore {
    /// The whole history as JSON, as a backup no sync problem can reach.
    public func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(attempts())
    }
}

/// For tests, and as a fallback so drills still work if the database can't open.
@MainActor
public final class InMemoryAttemptStore: AttemptStore {
    private var log: [Attempt] = []

    public init() {}

    public func append(_ attempt: Attempt) throws {
        log.append(attempt)
    }

    public func attempts() throws -> [Attempt] {
        log
    }
}

/// The shape of this model is held to CloudKit's rules so sync can be turned on later:
/// no unique constraints, no relationships, a default for every field, and raw strings.
/// After release, only add fields. Never rename or remove them.
@Model
final class AttemptRecord {
    var id = UUID()
    var book = ""
    var spot = ""
    var hand = ""
    var option = ""
    var cell = ""
    var answeredAt = Date.distantPast

    init(_ attempt: Attempt) {
        id = attempt.id
        book = attempt.book
        spot = attempt.spot
        hand = attempt.hand
        option = attempt.option
        cell = attempt.cell
        answeredAt = attempt.answeredAt
    }

    var attempt: Attempt {
        Attempt(id: id, book: book, spot: spot, hand: hand, option: option, cell: cell, answeredAt: answeredAt)
    }
}

@MainActor
public final class SwiftDataAttemptStore: AttemptStore {
    private let container: ModelContainer

    /// Sync stays off until it's turned on deliberately in a later milestone.
    public init(inMemory: Bool = false) throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        container = try ModelContainer(for: AttemptRecord.self, configurations: configuration)
    }

    public func append(_ attempt: Attempt) throws {
        container.mainContext.insert(AttemptRecord(attempt))
        try container.mainContext.save()
    }

    /// Oldest first. Attempts are deduplicated by id, since a database with no
    /// unique constraints can hold the same one twice once sync is on.
    public func attempts() throws -> [Attempt] {
        let descriptor = FetchDescriptor<AttemptRecord>(sortBy: [SortDescriptor(\.answeredAt)])
        var seen = Set<UUID>()
        return try container.mainContext.fetch(descriptor)
            .map(\.attempt)
            .filter { seen.insert($0.id).inserted }
    }
}
