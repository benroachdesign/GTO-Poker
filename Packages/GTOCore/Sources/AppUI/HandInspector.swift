import SwiftUI
import ChartData
import PokerDomain

/// One hand in detail: how it got here, and how it plays elsewhere.
struct HandInspector: View {
    let hand: String
    let journey: [HandStep]
    let comparison: HandComparison
    let onSelectSpot: (SpotKey) -> Void
    var onClose: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                VStack(spacing: 6) {
                    ForEach(journey) { step in
                        JourneyRow(step: step)
                    }
                }

                if comparison.entries.count > 1 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(comparison.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)

                        HStack(spacing: 4) {
                            ForEach(comparison.entries) { entry in
                                Button {
                                    onSelectSpot(entry.spot)
                                } label: {
                                    ComparisonChip(entry: entry)
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(hand)
                .font(.system(size: 24, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(Theme.textPrimary)

            Text("\(Int(HandGrid.getCombos(for: hand))) combos")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            Spacer()

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Theme.surfaceRaised, in: Circle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Close")
            }
        }
    }
}

private struct JourneyRow: View {
    let step: HandStep

    private var actionText: String {
        guard let action = step.action else { return "Already folded" }
        let title = step.spot.title(for: action)
        guard let size = step.sizeBB, action != .allIn else { return title }
        return "\(title) \(BetText.size(size))"
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(step.spot.situation)
                .font(.system(size: 13, weight: step.isCurrent ? .semibold : .regular))
                .foregroundStyle(step.isCurrent ? Theme.textPrimary : Theme.textSecondary)

            Spacer(minLength: 8)

            if let action = step.action {
                Circle()
                    .fill(action == .fold ? Theme.textTertiary : Theme.color(for: action))
                    .frame(width: 8, height: 8)
            }

            Text(actionText)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(step.action == nil ? Theme.textTertiary : Theme.textPrimary)
        }
        .lineLimit(1)
    }
}

private struct ComparisonChip: View {
    let entry: HandComparison.Entry

    private var fill: Color {
        entry.action.map(Theme.color(for:)) ?? .clear
    }

    var body: some View {
        Text(entry.seat.rawValue)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(entry.action == nil ? Theme.textTertiary : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(entry.isCurrent ? Color.white : entry.action == nil ? Theme.hairline : .clear, lineWidth: entry.isCurrent ? 2 : 1)
            }
    }
}

/// Finds a hand as you type it. Reads "ak" as AKs until an "o" says otherwise.
struct HandSearchField: View {
    @Binding var selectedHand: String?
    var isFocused: FocusState<Bool>.Binding

    @State private var text = ""

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)

            TextField("Find hand", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .focused(isFocused)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .focusEffectDisabled()
                .focusable(false) // Otherwise iPadOS moves here on the arrow keys, which are shortcuts in this app
                #endif
                .onChange(of: text) {
                    if let hand = HandGrid.parse(text) {
                        selectedHand = hand
                    }
                }
                .onSubmit(finish)
                .onKeyPress(.escape) {
                    finish()
                    return .handled
                }
        }
        .padding(.horizontal, 10)
        .frame(width: 124, height: 34)
        .background(Theme.surface, in: Capsule())
    }

    private func finish() {
        text = ""
        isFocused.wrappedValue = false
    }
}
