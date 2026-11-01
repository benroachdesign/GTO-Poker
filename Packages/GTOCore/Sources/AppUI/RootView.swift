import SwiftUI
import ChartData

public struct RootView: View {
    @State private var rangeManager = RangeManager()

    public init() {}

    public var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if let library = rangeManager.library {
                AppShell(library: library)
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
        .task { await rangeManager.load() }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 840)
        #endif
    }
}
