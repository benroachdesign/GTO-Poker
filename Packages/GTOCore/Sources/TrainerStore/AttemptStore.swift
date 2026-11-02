import Foundation
import SwiftData
import os
import Trainer

/// Keeps the attempt log. Attempts are only ever added, never changed.
@MainActor
public protocol AttemptStore: AnyObject {
    var iCloudContainer: String? { get } // Nil when answers stay on this device
    func append(_ attempt: Attempt) throws
    func attempts() throws -> [Attempt]
    /// Picks up anything added from outside this app, such as from another device.
    /// Returns whether there was anything new.
    func reloadIfChanged() throws -> Bool
}

extension AttemptStore {
    /// The whole history as JSON, as a backup no sync problem can reach.
    public func exportJSON() throws -> Data {
        try AttemptLog.json(attempts())
    }
}

/// For tests, and as a fallback so drills still work if the database can't open.
@MainActor
public final class InMemoryAttemptStore: AttemptStore {
    private var log: [Attempt] = []

    public let iCloudContainer: String? = nil

    public init() {}

    public func append(_ attempt: Attempt) throws {
        log.append(attempt)
    }

    public func attempts() throws -> [Attempt] {
        log
    }

    public func reloadIfChanged() throws -> Bool {
        false
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
    public let iCloudContainer: String?

    private let container: ModelContainer
    private var log: [Attempt]? // Held once read: it only grows, and a fetch took 0.3s at 10,000 answers
    private var ids = Set<UUID>()
    private var rowCount = 0 // Rows behind the log, which can include duplicates

    /// Keeps the log on this device only. A file puts it somewhere other than the
    /// app's usual place, which lets tests stand in for a second device.
    public init(inMemory: Bool = false, file: URL? = nil) throws {
        let configuration = if let file {
            ModelConfiguration(url: file, cloudKitDatabase: .none)
        } else {
            ModelConfiguration(isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        }
        container = try ModelContainer(for: AttemptRecord.self, configurations: configuration)
        iCloudContainer = nil
    }

    /// The same log in the same place, so answers saved before sync was turned on carry over,
    /// mirrored to an iCloud container. Only call this from a build signed for that container:
    /// CloudKit otherwise crashes the process from a background thread a moment later.
    public init(iCloudContainer identifier: String, file: URL? = nil) throws {
        let configuration = if let file {
            ModelConfiguration(url: file, cloudKitDatabase: .private(identifier))
        } else {
            ModelConfiguration(cloudKitDatabase: .private(identifier))
        }
        container = try ModelContainer(for: AttemptRecord.self, configurations: configuration)
        iCloudContainer = identifier
    }

    public func append(_ attempt: Attempt) throws {
        container.mainContext.insert(AttemptRecord(attempt))
        try container.mainContext.save()

        guard log != nil else { return }
        rowCount += 1
        if ids.insert(attempt.id).inserted {
            log?.append(attempt)
        }
    }

    /// Oldest first when read. Attempts are deduplicated by id, since a database with no
    /// unique constraints can hold the same one twice once it syncs.
    public func attempts() throws -> [Attempt] {
        if let log { return log }

        let descriptor = FetchDescriptor<AttemptRecord>(sortBy: [SortDescriptor(\.answeredAt)])
        let rows = try container.mainContext.fetch(descriptor)
        let attempts = rows.map(\.attempt).filter { ids.insert($0.id).inserted }
        rowCount = rows.count
        log = attempts
        return attempts
    }

    /// Counting is cheap, so this can run on every change without rereading the whole log.
    public func reloadIfChanged() throws -> Bool {
        guard log != nil else { return false } // Nothing is held, so the next read is fresh anyway

        let rows = try container.mainContext.fetchCount(FetchDescriptor<AttemptRecord>())
        guard rows != rowCount else { return false }

        log = nil
        ids = []
        return true
    }
}
