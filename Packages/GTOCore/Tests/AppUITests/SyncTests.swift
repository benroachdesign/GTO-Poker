import Foundation
import Testing
import ChartData
import PokerDomain
import Trainer
import TrainerStore
@testable import AppUI

@MainActor
struct SyncTests {
    private let library: ChartLibrary

    init() throws {
        library = try ChartLibrary.bundled()
    }

    private func missedAnswer(_ hand: String = "K5s") throws -> Attempt {
        let spot = try #require(library.spot(id: "|LJ"))
        let wrong = spot.primaryAction(for: hand) == .fold ? "R" : "F"
        return Attempt(book: library.book.book.id, spot: "|LJ", hand: hand, option: wrong, cell: spot.cellSignature(for: hand), answeredAt: .now)
    }

    @Test func answersFromAnotherDeviceReachDrillsAndProgress() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        // A second connection to one file stands in for CloudKit writing in another device's answers
        let file = folder.appendingPathComponent("log.store")
        let here = try SwiftDataAttemptStore(file: file)
        let there = try SwiftDataAttemptStore(file: file)

        let session = AppSession(library: library, store: here)
        session.refresh()
        #expect(session.drills.dueCount == 0)

        try there.append(try missedAnswer())
        session.sync.checkForChanges()

        #expect(session.drills.dueCount == 1)
        #expect(session.mastery.report.record.attempts == 1)
    }

    @Test func sessionsCreateEverythingFromOneStore() {
        let session = AppSession(library: library, store: InMemoryAttemptStore())
        #expect(session.sync.status == .off)
        #expect(session.explorer != nil)
    }

    /// CloudKit crashes the app if the container it's given isn't one the build is signed for.
    @Test(arguments: ["GTOPoker-iOS", "GTOPoker-macOS"])
    func thePermissionsMatchTheContainerInCode(file: String) throws {
        let entitlements = try entitlements(file)
        #expect(entitlements["com.apple.developer.icloud-container-identifiers"] as? [String] == [AppSession.iCloudContainer])
        #expect(entitlements["com.apple.developer.icloud-services"] as? [String] == ["CloudKit"])
    }

    @Test func theMacVersionIsAllowedOntoTheNetwork() throws {
        let entitlements = try entitlements("GTOPoker-macOS")
        #expect(entitlements["com.apple.security.network.client"] as? Bool == true)
        #expect(entitlements["com.apple.security.app-sandbox"] as? Bool == true)
    }

    private func entitlements(_ name: String) throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // AppUITests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // GTOCore
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("App/\(name).entitlements"))
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }
}
