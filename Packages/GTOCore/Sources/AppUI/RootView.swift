import SwiftUI
import ChartData

public struct RootView: View {
    private let syncsWithICloud: Bool

    @State private var rangeManager = RangeManager()
    @State private var session: AppSession?

    /// Only pass true from a build signed with the iCloud permissions. Without them CloudKit
    /// crashes the process from a background thread, so there's no error to catch and fall back from.
    public init(syncsWithICloud: Bool = false) {
        self.syncsWithICloud = syncsWithICloud
    }

    public var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if let session {
                AppShell(session: session)
            } else if let error = rangeManager.loadError {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(32)
            }
        }
        .environment(rangeManager)
        .preferredColorScheme(.dark)
        .task {
            await rangeManager.load()

            if session == nil, let library = rangeManager.library {
                session = AppSession(library: library, syncsWithICloud: syncsWithICloud)
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 840)
        #endif
    }
}
