import SwiftUI

@main
struct GTOPokerApp: App {
    @StateObject private var rangeManager = RangeManager()
    @StateObject private var gameState = GameState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(rangeManager)
                .environmentObject(gameState)
                .frame(minWidth: 500, minHeight: 600)
        }
        .windowStyle(HiddenTitleBarWindowStyle())
    }
}
