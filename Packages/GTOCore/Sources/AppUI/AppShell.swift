import SwiftUI
import os
import ChartData
import PokerDomain
import TrainerStore

enum AppSection: String, CaseIterable, Identifiable {
    case charts, drills, progress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .charts: return "Charts"
        case .drills: return "Drills"
        case .progress: return "Progress"
        }
    }

    var systemImage: String {
        switch self {
        case .charts: return "square.grid.3x3.fill"
        case .drills: return "target"
        case .progress: return "chart.bar.fill"
        }
    }
}

/// The app's sections. Each keeps its place while you're in another, so a
/// drill can stop to look something up in the charts and carry on afterwards.
struct AppShell: View {
    private static let lastSpotKey = "explorer.lastSpot"

    @AppStorage(lastSpotKey) private var lastSpot = ""
    @State private var section = AppSection.charts
    @State private var explorer: ExplorerModel?
    @State private var drills: DrillModel
    @State private var mastery: MasteryModel

    init(library: ChartLibrary) {
        let saved = UserDefaults.standard.string(forKey: Self.lastSpotKey)
        let store = Self.makeStore()
        _explorer = State(initialValue: ExplorerModel(library: library, startingAt: saved))
        _drills = State(initialValue: DrillModel(library: library, store: store))
        _mastery = State(initialValue: MasteryModel(library: library, store: store))
    }

    var body: some View {
        sections
            .onChange(of: section, refresh)
            .task { refresh() }
    }

    @ViewBuilder
    private var sections: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            SectionSwitcher(selection: $section, dueCount: drills.dueCount)
                .padding(.top, 6)

            switch section {
            case .charts: charts
            case .drills: drillsSection
            case .progress: progress
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
            .badge(drills.dueCount)
            Tab(AppSection.progress.title, systemImage: AppSection.progress.systemImage, value: AppSection.progress) {
                progress
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

    private var progress: some View {
        MasteryView(
            model: mastery,
            onReview: {
                drills.startReview()
                section = .drills
            },
            onDrill: { section = .drills },
            onOpenSpot: { open($0, hand: nil) }
        )
    }

    /// Reloads what's worked out from the log, since answers made in Drills change what the other sections show.
    private func refresh() {
        drills.refreshHistory()
        mastery.refresh()
    }

    /// Jumps to that exact spot, and hand if there is one, in the charts.
    private func open(_ spot: SpotKey, hand: String?) {
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
    let dueCount: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, section in
                Button {
                    selection = section
                } label: {
                    HStack(spacing: 6) {
                        Label(section.title, systemImage: section.systemImage)

                        if section == .drills, dueCount > 0 {
                            Text(dueCount.formatted())
                                .font(.system(size: 11, weight: .bold))
                                .monospacedDigit()
                                .padding(.horizontal, 6)
                                .frame(height: 16)
                                .background(Theme.raise, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(section == selection ? Color.black : Theme.textSecondary)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(section == selection ? Color.white : .clear, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
        .padding(3)
        .background(Theme.surface, in: Capsule())
    }
}
#endif
