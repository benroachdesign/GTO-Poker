import SwiftUI
import ChartData

public struct RootView: View {
    @StateObject private var rangeManager = RangeManager()
    @StateObject private var gameState = GameState()

    public init() {}

    public var body: some View {
        ContentView()
            .environmentObject(rangeManager)
            .environmentObject(gameState)
            #if os(macOS)
            .frame(minWidth: 500, minHeight: 600)
            #endif
    }
}
