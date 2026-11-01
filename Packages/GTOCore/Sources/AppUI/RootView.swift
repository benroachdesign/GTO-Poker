import SwiftUI
import ChartData

public struct RootView: View {
    @State private var rangeManager = RangeManager()

    public init() {}

    public var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if let library = rangeManager.library {
                ExplorerHost(library: library)
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
        .frame(minWidth: 600, minHeight: 800)
        #endif
    }
}

/// Keeps the explorer's model alive, and brings you back to the last spot you were on.
private struct ExplorerHost: View {
    private static let lastSpotKey = "explorer.lastSpot"

    @AppStorage(lastSpotKey) private var lastSpot = ""
    @State private var model: ExplorerModel?

    init(library: ChartLibrary) {
        let saved = UserDefaults.standard.string(forKey: Self.lastSpotKey)
        _model = State(initialValue: ExplorerModel(library: library, startingAt: saved))
    }

    var body: some View {
        if let model {
            ExplorerView(model: model)
                .onChange(of: model.key) {
                    lastSpot = model.key.id
                }
        }
    }
}
