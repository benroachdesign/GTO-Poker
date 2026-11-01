import SwiftUI
import Observation
import os
import ChartData
import PokerDomain
import Trainer
import TrainerStore

/// The attempt log as a file you can keep. Sync problems can't reach a copy you saved yourself.
/// It's only written out if you actually export it.
struct HistoryFile: Transferable {
    let attempts: [Attempt]

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { try AttemptLog.json($0.attempts) }
            .suggestedFileName("gto-poker-history.json")
    }
}

/// What everything worked out from the attempt log depends on. The log only ever grows
/// and hands fall due at the start of a day, so nothing needs redoing unless this changes.
struct HistoryVersion: Equatable {
    let attemptCount: Int
    let day: Date

    init(attempts: [Attempt], now: Date) {
        attemptCount = attempts.count
        day = Calendar.current.startOfDay(for: now)
    }
}

@MainActor
@Observable
final class MasteryModel {
    private(set) var report: MasteryReport
    private(set) var historyFile: HistoryFile?

    private let library: ChartLibrary
    private let store: any AttemptStore
    private let now: () -> Date
    private var version: HistoryVersion?
    private let logger = Logger(subsystem: "com.benroachdesign.GTOPoker", category: "progress")

    init(library: ChartLibrary, store: any AttemptStore, now: @escaping () -> Date = Date.init) {
        self.library = library
        self.store = store
        self.now = now
        report = MasteryReport(attempts: [], library: library, now: now())
    }

    func refresh() {
        do {
            let attempts = try store.attempts()
            let version = HistoryVersion(attempts: attempts, now: now())
            guard version != self.version else { return }

            self.version = version
            report = MasteryReport(attempts: attempts, library: library, now: now())
            historyFile = report.hasHistory ? HistoryFile(attempts: attempts) : nil
        } catch {
            logger.error("Failed to build the report: \(error)")
        }
    }
}

struct MasteryView: View {
    let model: MasteryModel
    let onReview: () -> Void
    let onDrill: () -> Void
    let onOpenSpot: (SpotKey) -> Void

    private var report: MasteryReport { model.report }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if report.hasHistory {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        summary

                        if !report.weakest.isEmpty {
                            weakestSpots
                        }

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16, alignment: .top)], spacing: 16) {
                            MasterySection(title: "By stage", groups: report.stages)
                            MasterySection(title: "By seat", groups: report.seats)
                        }

                        Text("Mastery counts the hands at the edge of a range most, and grows as they stay right over weeks.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let file = model.historyFile {
                            ShareLink(item: file, preview: SharePreview("GTO Poker history")) {
                                Label("Export history", systemImage: "square.and.arrow.up")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                emptyState
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Progress")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(BetText.mastery(report.overall))
                        .font(.system(size: 44, weight: .bold))
                        .tracking(-1)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)

                    Text("mastered")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }

                Text("\(BetText.hands(report.record.attempts)) answered, \(BetText.percent(report.record.accuracy)) correct")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }

            if report.dueCount > 0 {
                ReviewPrompt(dueCount: report.dueCount, onReview: onReview)
            }
        }
    }

    private var weakestSpots: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weakest spots")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)

            ForEach(report.weakest) { spot in
                Button {
                    onOpenSpot(spot.key)
                } label: {
                    WeakSpotRow(spot: spot)
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("Your progress shows up here")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            Text("Answer a few drills and this fills in, with what's due for review and where you're weakest.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            Button(action: onDrill) {
                Text("Go to Drills")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 20)
                    .frame(height: 44)
                    .background(Color.white, in: Capsule())
            }
            .buttonStyle(PressableStyle())
        }
        .padding(32)
        .frame(maxWidth: 420)
    }
}

private struct MasterySection: View {
    let title: String
    let groups: [MasteryGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)

            ForEach(groups) { group in
                MasteryRow(group: group)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct MasteryRow: View {
    let group: MasteryGroup

    /// Answers and accuracy move day to day, while the mastery bar moves over weeks.
    private var activity: String {
        guard group.record.attempts > 0 else { return "Not drilled yet" }
        return "\(group.record.attempts.formatted()) answered, \(BetText.percent(group.record.accuracy)) correct"
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text(activity)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)

                Text(BetText.mastery(group.mastery))
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }

            GeometryReader { geometry in
                Capsule()
                    .fill(Theme.surfaceRaised)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Theme.textPrimary)
                            .frame(width: geometry.size.width * group.mastery)
                    }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WeakSpotRow: View {
    let spot: WeakSpot

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(spot.key.hero.rawValue)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(spot.key.situation)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: 0)

            Text("\(spot.record.correct) of \(spot.record.attempts)")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }
}
