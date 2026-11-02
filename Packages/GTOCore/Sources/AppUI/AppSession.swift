import Foundation
import os
import ChartData
import TrainerStore

/// Everything that should exist exactly once per launch. A view's init can run many times,
/// and two connections to one iCloud-synced database would fight each other.
@MainActor
final class AppSession {
    static let lastSpotKey = "explorer.lastSpot"
    static let iCloudContainer = "iCloud.com.benroachdesign.GTOPoker"

    let explorer: ExplorerModel?
    let drills: DrillModel
    let mastery: MasteryModel
    let sync: SyncMonitor

    /// The monitor comes first because CloudKit starts work the moment the store opens.
    convenience init(library: ChartLibrary, syncsWithICloud: Bool) {
        let sync = SyncMonitor()
        self.init(library: library, store: Self.openStore(syncsWithICloud: syncsWithICloud), sync: sync)
    }

    init(library: ChartLibrary, store: any AttemptStore, sync: SyncMonitor = SyncMonitor()) {
        let saved = UserDefaults.standard.string(forKey: Self.lastSpotKey)
        let drills = DrillModel(library: library, store: store)
        let mastery = MasteryModel(library: library, store: store)

        explorer = ExplorerModel(library: library, startingAt: saved)
        self.drills = drills
        self.mastery = mastery
        self.sync = sync

        sync.attach(to: store) {
            drills.refreshHistory()
            mastery.refresh()
        }
    }

    /// Reloads what's worked out from the log, since answers made in Drills change what the other sections show.
    func refresh() {
        drills.refreshHistory()
        mastery.refresh()
    }

    /// Falls back in steps, so drills always work: without iCloud they stay on this
    /// device, and without a database at all they just won't remember anything.
    private static func openStore(syncsWithICloud: Bool) -> any AttemptStore {
        let logger = Logger(subsystem: "com.benroachdesign.GTOPoker", category: "drills")

        if syncsWithICloud {
            do {
                return try SwiftDataAttemptStore(iCloudContainer: iCloudContainer)
            } catch {
                logger.error("Failed to open the synced log: \(error)")
            }
        }

        do {
            return try SwiftDataAttemptStore()
        } catch {
            logger.error("Failed to open the attempt log: \(error)")
            return InMemoryAttemptStore()
        }
    }
}
