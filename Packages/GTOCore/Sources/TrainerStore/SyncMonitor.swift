import CloudKit
import CoreData
import Foundation
import Observation
import os

public enum SyncStatus: Equatable, Sendable {
    case off       // Answers stay on this device
    case waiting   // On, but nothing has been confirmed yet
    case synced
    case signedOut // Needs an iCloud account. Answers are safe here until then
    case failed    // The last attempt failed. Answers are safe here and it will retry

    /// CloudKit reports nothing unless asked, so this is how a quiet failure gets noticed.
    func applying(_ event: SyncEvent) -> SyncStatus {
        guard self != .off, self != .signedOut, event.isFinished else { return self }
        guard event.succeeded else { return .failed }

        switch event.kind {
        case .transfer: return .synced
        case .setup: return self == .synced ? .synced : .waiting
        }
    }

    /// The account is the one thing worth asking about directly. Without one, CloudKit
    /// only ever reports a failed setup, which reads as a fault rather than a next step.
    func applying(hasAccount: Bool) -> SyncStatus {
        guard self != .off else { return .off }
        if !hasAccount { return .signedOut }
        return self == .signedOut ? .waiting : self
    }
}

/// One step of CloudKit's work, reduced to the parts the app cares about.
struct SyncEvent: Equatable, Sendable {
    enum Kind: Sendable {
        case setup, transfer
    }

    let kind: Kind
    let isFinished: Bool
    let succeeded: Bool

    init(kind: Kind, isFinished: Bool, succeeded: Bool) {
        self.kind = kind
        self.isFinished = isFinished
        self.succeeded = succeeded
    }

    init(_ event: NSPersistentCloudKitContainer.Event) {
        self.init(kind: event.type == .setup ? .setup : .transfer, isFinished: event.endDate != nil, succeeded: event.succeeded)
    }
}

/// Watches CloudKit's work on the attempt log. Reports how it's going, and passes
/// on answers as they arrive from other devices.
@MainActor
@Observable
public final class SyncMonitor {
    private static let settleDelay = Duration.seconds(1) // Imports arrive in bursts

    public private(set) var status = SyncStatus.waiting

    @ObservationIgnored private var store: (any AttemptStore)?
    @ObservationIgnored private var onChange: (@MainActor () -> Void)?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var pendingCheck: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "com.benroachdesign.GTOPoker", category: "sync")

    /// Listens straight away. CloudKit starts work the moment a store opens, so
    /// this has to exist first or an early failure goes unnoticed.
    public init() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: nil) { [weak self] notification in
                let key = NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                guard let event = notification.userInfo?[key] as? NSPersistentCloudKitContainer.Event else { return }

                let summary = SyncEvent(event)
                Task { @MainActor in self?.handle(summary) }
            },
            center.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor in self?.scheduleCheck() }
            },
            center.addObserver(forName: .CKAccountChanged, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor in await self?.checkAccount() }
            }
        ]
    }

    public func attach(to store: any AttemptStore, onChange: @escaping @MainActor () -> Void) {
        self.store = store
        self.onChange = onChange

        guard store.iCloudContainer != nil else {
            status = .off
            return
        }
        Task { await checkAccount() }
    }

    func handle(_ event: SyncEvent) {
        status = status.applying(event)
        if event.isFinished, event.kind == .transfer {
            scheduleCheck()
        }
    }

    /// Also runs for this device's own saves, which is fine because counting rows is cheap.
    public func checkForChanges() {
        do {
            if try store?.reloadIfChanged() == true {
                onChange?()
            }
        } catch {
            logger.error("Failed to check for new answers: \(error)")
        }
    }

    private func checkAccount() async {
        guard let identifier = store?.iCloudContainer else { return }

        do {
            let account = try await CKContainer(identifier: identifier).accountStatus()
            status = status.applying(hasAccount: account != .noAccount && account != .restricted)
        } catch {
            logger.error("Failed to check the iCloud account: \(error)")
        }
    }

    private func scheduleCheck() {
        guard status != .off else { return }

        pendingCheck?.cancel()
        pendingCheck = Task {
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled else { return }
            checkForChanges()
        }
    }
}
