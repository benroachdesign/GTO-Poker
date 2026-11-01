import SwiftUI
import ChartData

/// The legend and the way forward in one control: what the range does here, and where each choice leads.
struct ChoiceBar: View {
    let choices: [SpotChoice]
    var shortcutsEnabled = true
    let onChoose: (SpotChoice) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ShareBar(choices: choices)
                .frame(height: 5)

            HStack(spacing: 8) {
                ForEach(choices) { choice in
                    Button {
                        onChoose(choice)
                    } label: {
                        ChoiceLabel(choice: choice)
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(choice.destination == nil)
                    .keyboardShortcut(shortcutsEnabled ? choice.shortcut : nil)
                }
            }
        }
    }
}

extension SpotChoice {
    /// The option's own letter: R, A, C or F.
    var shortcut: KeyboardShortcut? {
        code.lowercased().first.map { KeyboardShortcut(KeyEquivalent($0), modifiers: []) }
    }
}

private struct ShareBar: View {
    let choices: [SpotChoice]

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(choices) { choice in
                    let spacing = CGFloat(choices.count - 1) * 2
                    Rectangle()
                        .fill(choice.kind == .fold ? Theme.surfaceRaised : Theme.color(for: choice.kind))
                        .frame(width: max(0, (geometry.size.width - spacing) * choice.share))
                }
            }
            .animation(Theme.motion, value: choices.map(\.share))
        }
        .clipShape(Capsule())
    }
}

private struct ChoiceLabel: View {
    let choice: SpotChoice

    private var detail: String {
        guard let size = choice.sizeBB else { return BetText.share(choice.share) }
        return "\(BetText.size(size)) · \(BetText.share(choice.share))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle()
                    .fill(choice.kind == .fold ? Theme.textTertiary : Theme.color(for: choice.kind))
                    .frame(width: 8, height: 8)
                Text(choice.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                if choice.destination != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }
}
