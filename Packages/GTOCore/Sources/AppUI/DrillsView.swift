import SwiftUI
import ChartData
import PokerDomain
import Trainer

struct DrillsView: View {
    @Bindable var model: DrillModel
    var isActive = true
    let onOpenSpot: (SpotKey, String) -> Void

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            switch model.phase {
            case .setup:
                DrillSetupView(model: model)
            case .question, .answered:
                DrillSessionView(model: model, isActive: isActive, onOpenSpot: onOpenSpot)
            case .summary:
                DrillSummaryView(model: model, onOpenSpot: onOpenSpot)
            }
        }
    }
}

private struct DrillSetupView: View {
    @Bindable var model: DrillModel

    private var historyText: String {
        let totals = model.historyTotals
        guard totals.attempts > 0 else { return "Build a session. Harder hands come up more often." }
        let hands = totals.attempts == 1 ? "1 hand" : "\(totals.attempts.formatted()) hands"
        return "\(hands) answered, \(BetText.share(totals.accuracy)) correct"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Drills")
                        .font(.system(size: 28, weight: .bold))
                        .tracking(-0.5)
                        .foregroundStyle(Theme.textPrimary)
                    Text(historyText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }

                if model.isLocked {
                    Text("Drills unlock once every item in the chart review has a ruling.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    filters
                    startButton
                }
            }
            .padding(20)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private var filters: some View {
        FilterGroup(title: "Seats") {
            FilterChip(title: "All", isOn: model.scope.seats.isEmpty) { model.scope.seats = [] }
            ForEach(Position.preflopSequence, id: \.self) { seat in
                FilterChip(title: seat.rawValue, isOn: model.scope.seats.contains(seat)) {
                    model.scope.seats.formSymmetricDifference([seat])
                }
            }
        }

        FilterGroup(title: "Stage") {
            FilterChip(title: "All", isOn: model.scope.stages.isEmpty) { model.scope.stages = [] }
            ForEach(DrillStage.allCases, id: \.self) { stage in
                FilterChip(title: stage.title, isOn: model.scope.stages.contains(stage)) {
                    model.scope.stages.formSymmetricDifference([stage])
                }
            }
        }

        FilterGroup(title: "Focus") {
            FilterChip(title: "Everything", isOn: model.scope.focus == .everything) { model.scope.focus = .everything }
            FilterChip(title: "Weakest spots", isOn: model.scope.focus == .weakest) { model.scope.focus = .weakest }
        }

        FilterGroup(title: "Length") {
            ForEach(DrillModel.sessionLengths, id: \.self) { length in
                FilterChip(title: "\(length) hands", isOn: model.length == length) { model.length = length }
            }
        }
    }

    private var startButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(Theme.motion) { model.start() }
            } label: {
                Text("Start")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(model.canStart ? .white : Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(model.canStart ? Theme.raise : Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(PressableStyle())
            .disabled(!model.canStart)

            Text(model.matchingSpotCount == 0 ? "No spots match. The BB never opens." : "\(model.matchingSpotCount) spots")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

private struct FilterGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 6)], alignment: .leading, spacing: 6) {
                content
            }
        }
    }
}

private struct FilterChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isOn ? Color.black : Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(isOn ? Color.white : Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct DrillSummaryView: View {
    @Bindable var model: DrillModel
    let onOpenSpot: (SpotKey, String) -> Void

    private var accuracy: Double {
        model.answers.isEmpty ? 0 : Double(model.correctCount) / Double(model.answers.count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(model.correctCount) of \(model.answers.count)")
                        .font(.system(size: 44, weight: .bold))
                        .tracking(-1)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(BetText.share(accuracy)) correct")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)

                    if model.saveFailed {
                        Text("Some answers couldn't be saved to your history.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.raise)
                    }
                }

                if !model.misses.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("To review")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)

                        ForEach(model.misses) { miss in
                            Button {
                                onOpenSpot(miss.question.spot, miss.question.hand)
                            } label: {
                                MissRow(miss: miss)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }

                VStack(spacing: 8) {
                    Button {
                        withAnimation(Theme.motion) { model.start() }
                    } label: {
                        Text("Drill again")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Theme.raise, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())

                    Button("Change session", action: model.finish)
                        .buttonStyle(PressableStyle())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(height: 40)
                }
            }
            .padding(20)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct MissRow: View {
    let miss: DrillAnswer

    var body: some View {
        HStack(spacing: 12) {
            Text(miss.question.hand)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(miss.question.spot.hero.rawValue), \(miss.question.spot.situation.lowercasedFirst)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("You chose \(miss.chosen.title). Best was \(miss.best?.title ?? "another play").")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }
}

private extension String {
    var lowercasedFirst: String {
        prefix(1).lowercased() + dropFirst()
    }
}
