import SwiftUI
import os
import ChartData
import PokerDomain
import TrainerStore

enum AppSection: String, CaseIterable, Identifiable {
    case charts, drills

    var id: String { rawValue }

    var title: String {
        switch self {
        case .charts: return "Charts"
        case .drills: return "Drills"
        }
    }

    var systemImage: String {
        switch self {
        case .charts: return "square.grid.3x3.fill"
        case .drills: return "target"
        }
    }
}

/// The app's sections. Each keeps its place while you're in the other, so a
/// drill can stop to look something up in the charts and carry on afterwards.
struct AppShell: View {
    private static let lastSpotKey = "explorer.lastSpot"

    @AppStorage(lastSpotKey) private var lastSpot = ""
    @State private var section = AppSection.charts
    @State private var explorer: ExplorerModel?
    @State private var drills: DrillModel

    init(library: ChartLibrary) {
        let saved = UserDefaults.standard.string(forKey: Self.lastSpotKey)
        _explorer = State(initialValue: ExplorerModel(library: library, startingAt: saved))
        _drills = State(initialValue: DrillModel(library: library, store: Self.makeStore()))
    }

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            SectionSwitcher(selection: $section)
                .padding(.top, 6)

            switch section {
            case .charts: charts
            case .drills: drillsSection
            }
        }
        #else
        TabView(selection: $section) {
            Tab(AppSection.charts.title, systemImage: AppSection.charts.systemImage, value: AppSection.charts) {
                charts
            }
            Tab(AppSection.drills.title, systemImage: AppSection.drills.systemImage, value: AppSection.drills) {
                drillsSection
            }
        }
        .tint(Theme.textPrimary)
        #endif
    }

    @ViewBuilder
    private var charts: some View {
        if let explorer {
            ExplorerView(model: explorer, isActive: section == .charts)
                .onChange(of: explorer.key) {
                    lastSpot = explorer.key.id
                }
        }
    }

    private var drillsSection: some View {
        DrillsView(model: drills, isActive: section == .drills, onOpenSpot: open)
    }

    /// Jumps from a drill to that exact spot and hand in the charts.
    private func open(_ spot: SpotKey, hand: String) {
        explorer?.go(to: spot)
        explorer?.selectedHand = hand
        section = .charts
    }

    /// Drills still work without a database. They just won't remember anything.
    private static func makeStore() -> any AttemptStore {
        do {
            return try SwiftDataAttemptStore()
        } catch {
            Logger(subsystem: "com.benroachdesign.GTOPoker", category: "drills")
                .error("Failed to open the attempt log: \(error)")
            return InMemoryAttemptStore()
        }
    }
}

#if os(macOS)
private struct SectionSwitcher: View {
    @Binding var selection: AppSection

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    Label(section.title, systemImage: section.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(section == selection ? Color.black : Theme.textSecondary)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(section == selection ? Color.white : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(section == .charts ? "1" : "2", modifiers: .command)
            }
        }
        .padding(3)
        .background(Theme.surface, in: Capsule())
    }
}
#endif
