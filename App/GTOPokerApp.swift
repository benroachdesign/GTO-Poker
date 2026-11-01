import SwiftUI
import AppUI

@main
struct GTOPokerApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 840)
        .windowStyle(HiddenTitleBarWindowStyle())
        #endif
    }
}
