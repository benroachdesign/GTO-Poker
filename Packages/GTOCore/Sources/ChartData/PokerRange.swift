import Foundation
import Observation
import os
import PokerDomain

/// A chart as a flat hand -> action map, for comparing one against another.
public struct PokerRange: Identifiable, Sendable {
    public let id: String
    public let actions: [String: OptionKind]

    public init(spot: Spot) {
        id = spot.id
        var actions: [String: OptionKind] = [:]
        for hand in HandGrid.allHands {
            actions[hand] = spot.primaryAction(for: hand)
        }
        self.actions = actions
    }

    private init(id: String, actions: [String: OptionKind]) {
        self.id = id
        self.actions = actions
    }

    /// This range as it was before a repair.
    public func reverting(_ changes: [CellChange]) -> PokerRange {
        var actions = actions
        for change in changes {
            actions[change.hand] = OptionKind(code: change.was)
        }
        return PokerRange(id: "\(id)#before", actions: actions)
    }
}

@MainActor
@Observable
public final class RangeManager {
    public private(set) var library: ChartLibrary?
    public private(set) var loadError: String?

    private let logger = Logger(subsystem: "com.benroachdesign.GTOPoker", category: "charts")

    public init() {}

    /// Decodes the bundled book off the main actor, so launch never waits on it.
    public func load() async {
        guard library == nil else { return }

        let clock = ContinuousClock()
        let start = clock.now
        do {
            let library = try await Self.loadBundled()
            self.library = library
            logger.info("Loaded \(library.book.spots.count) spots in \(clock.now - start, privacy: .public)")
        } catch {
            loadError = String(describing: error)
            logger.error("Failed to load ranges: \(error)")
        }
    }

    public func range(forSpot id: String) -> PokerRange? {
        library?.spot(id: id).map(PokerRange.init(spot:))
    }

    @concurrent
    private nonisolated static func loadBundled() async throws -> ChartLibrary {
        try ChartLibrary.bundled()
    }
}
