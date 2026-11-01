import SwiftUI
import ChartData
import PokerDomain
import Trainer

/// The explorer's frame with the grid face down: you decide first, then the range colours in around your hand.
struct DrillSessionView: View {
    @Bindable var model: DrillModel
    var isActive = true // Tabs stay alive when hidden, so a hidden one must not take key presses
    let onOpenSpot: (SpotKey, String) -> Void

    private static let wideWidth: CGFloat = 900
    private static let mediumWidth: CGFloat = 600
    private static let gutter: CGFloat = 16
    private static let gap: CGFloat = 12
    private static let correctPause = Duration.milliseconds(900)

    private var isAnswered: Bool { model.currentAnswer != nil }

    /// Set only while a right answer is on screen, which starts the pause before moving on.
    private var autoAdvanceID: UUID? {
        guard let answer = model.currentAnswer, answer.isCorrect else { return nil }
        return answer.id
    }

    var body: some View {
        GeometryReader { geometry in
            let size = CGSize(width: geometry.size.width - Self.gutter * 2, height: geometry.size.height)

            VStack(spacing: Self.gap) {
                progressRow

                if geometry.size.width >= Self.wideWidth {
                    wideLayout(size)
                } else if geometry.size.width >= Self.mediumWidth {
                    mediumLayout(size)
                } else {
                    compactLayout(size)
                }
            }
            .padding(.horizontal, Self.gutter)
            .padding(.top, 8)
        }
        .background(Theme.background.ignoresSafeArea())
        .background {
            // Return moves on even when no Next button is showing, such as during the pause after a right answer
            Button("Next", action: advance)
                .keyboardShortcut(isActive ? KeyboardShortcut(.return, modifiers: []) : nil)
                .disabled(!isAnswered)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .task(id: autoAdvanceID) {
            guard autoAdvanceID != nil else { return }
            try? await Task.sleep(for: Self.correctPause)
            guard !Task.isCancelled else { return }
            advance()
        }
    }

    // MARK: - Layouts

    private func compactLayout(_ size: CGSize) -> some View {
        let reserved = 32 + 60 + size.width + 70 + Self.gap * 4 + 16
        let panelHeight = min(max(size.height - reserved, 150), 300)

        return ScrollView {
            VStack(spacing: Self.gap) {
                header
                grid
                answerBar
                bottomPanel.frame(height: panelHeight)
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    /// A mistake is the moment to stop and look, so the table gives way to the explanation.
    @ViewBuilder
    private var bottomPanel: some View {
        if let answer = model.currentAnswer, !answer.isCorrect {
            feedback(for: answer)
        } else {
            table
        }
    }

    private func mediumLayout(_ size: CGSize) -> some View {
        let gridSide = min(size.width, size.height * 0.56)

        return VStack(spacing: Self.gap) {
            header
            grid.frame(width: gridSide, height: gridSide)
            answerBar

            HStack(alignment: .top, spacing: Self.gap) {
                table
                sidePanel
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.bottom, Self.gap)
    }

    private func wideLayout(_ size: CGSize) -> some View {
        let sideWidth = min(max(size.width * 0.34, 340), 420)
        let gridSide = min(size.width - sideWidth - Self.gap * 2, size.height - 138)

        return HStack(alignment: .top, spacing: Self.gap * 2) {
            VStack(alignment: .leading, spacing: Self.gap) {
                header
                grid.frame(width: gridSide, height: gridSide)
            }
            .frame(width: gridSide)

            VStack(spacing: Self.gap) {
                table.frame(height: 220)
                answerBar
                sidePanel
            }
            .frame(width: sideWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.bottom, Self.gap)
    }

    // MARK: - Pieces

    private var progressRow: some View {
        HStack(spacing: 12) {
            Text("\(model.questionNumber) of \(model.sessionLength)")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)

            GeometryReader { geometry in
                Capsule()
                    .fill(Theme.surfaceRaised)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Theme.textPrimary)
                            .frame(width: geometry.size.width * Double(model.answers.count) / Double(max(model.sessionLength, 1)))
                    }
                    .animation(Theme.motion, value: model.answers.count)
            }
            .frame(height: 4)

            Button("End", action: model.end)
                .buttonStyle(PressableStyle())
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .keyboardShortcut(isActive ? KeyboardShortcut(.escape, modifiers: []) : nil)
        }
        .frame(height: 32)
    }

    @ViewBuilder
    private var header: some View {
        if let question = model.question {
            HStack(alignment: .center, spacing: Self.gap) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(question.spot.hero.rawValue)
                            .font(.system(size: 28, weight: .bold))
                            .tracking(-0.5)
                            .foregroundStyle(Theme.textPrimary)

                        Text(question.spot.situation)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    verdict
                }

                Spacer(minLength: 0)

                HandCards(hand: question.hand, seed: Int(question.id.uuid.0))
                    .id(question.id)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
            .frame(height: 60)
        }
    }

    @ViewBuilder
    private var verdict: some View {
        if let answer = model.currentAnswer {
            Text(verdictText(for: answer))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(answer.isCorrect ? Theme.correct : Theme.raise)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } else {
            Text("What's your play?")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func verdictText(for answer: DrillAnswer) -> String {
        if answer.isCorrect { return "Correct" }
        guard let best = answer.best else { return "Not the best play" }
        return "Best play: \(best.displayName)"
    }

    private var grid: some View {
        RangeGridView(
            cells: isAnswered ? model.revealedCells : model.concealedCells,
            selected: model.question?.hand
        )
    }

    private var answerBar: some View {
        AnswerBar(choices: model.choices, toCall: model.table?.toCall, answer: model.currentAnswer, shortcutsEnabled: isActive) { choice in
            model.answer(code: choice.code)
        }
    }

    @ViewBuilder
    private var table: some View {
        if let state = model.table {
            TableView(state: state, canTap: { _ in false }, onTap: { _ in })
        }
    }

    @ViewBuilder
    private var sidePanel: some View {
        if let answer = model.currentAnswer, !answer.isCorrect {
            feedback(for: answer)
        } else {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func feedback(for answer: DrillAnswer) -> some View {
        VStack(spacing: 8) {
            HandInspector(
                hand: answer.question.hand,
                journey: model.library.journey(of: answer.question.hand, to: answer.question.spot),
                comparison: model.library.comparison(of: answer.question.hand, at: answer.question.spot),
                onSelectSpot: { onOpenSpot($0, answer.question.hand) }
            )

            Button(action: advance) {
                Text(model.answers.count >= model.sessionLength ? "See results" : "Next hand")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(PressableStyle())
        }
    }

    private func advance() {
        withAnimation(Theme.motion) {
            model.next()
        }
    }
}

extension SpotChoice {
    /// "3-Bet 10.5bb", or just "All-in" where the size says nothing new.
    var displayName: String {
        guard let sizeBB, kind != .allIn else { return title }
        return "\(title) \(BetText.size(sizeBB))"
    }
}

/// The hero's options. Before answering they show what each costs, not how often it's
/// taken, so the numbers can't give the answer away.
private struct AnswerBar: View {
    let choices: [SpotChoice]
    let toCall: Double?
    let answer: DrillAnswer?
    let shortcutsEnabled: Bool
    let onChoose: (SpotChoice) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(choices) { choice in
                Button {
                    onChoose(choice)
                } label: {
                    AnswerLabel(choice: choice, toCall: toCall, answer: answer)
                }
                .buttonStyle(PressableStyle())
                .disabled(answer != nil)
                .keyboardShortcut(shortcutsEnabled ? choice.shortcut : nil)
            }
        }
    }
}

private struct AnswerLabel: View {
    let choice: SpotChoice
    let toCall: Double?
    let answer: DrillAnswer?

    private var isBest: Bool { answer?.best?.kind == choice.kind }
    private var isWrongPick: Bool { answer?.chosen.kind == choice.kind && answer?.isCorrect == false }

    private var detail: String? {
        if answer != nil { return BetText.share(choice.share) }

        switch choice.kind {
        case .raise, .allIn: return choice.sizeBB.map(BetText.size)
        case .call: return toCall.map(BetText.size)
        case .fold: return nil
        }
    }

    private var background: Color {
        guard isBest else { return Theme.surface }
        return choice.kind == .fold ? Theme.surfaceRaised : Theme.color(for: choice.kind)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if answer == nil {
                    Circle()
                        .fill(choice.kind == .fold ? Theme.textTertiary : Theme.color(for: choice.kind))
                        .frame(width: 8, height: 8)
                }
                Text(choice.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Spacer(minLength: 0)

                if isBest {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                } else if isWrongPick {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.raise)
                }
            }

            Text(detail ?? " ")
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(isBest ? Theme.textPrimary.opacity(0.8) : Theme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            if isWrongPick {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.raise, lineWidth: 1.5)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Two real cards rather than a code like "AQo": the suits are decoration, but this is what a hand looks like.
struct HandCards: View {
    let hand: String
    let seed: Int

    private static let suits = ["spade", "heart", "diamond", "club"]

    private var cards: [(rank: String, suit: String)] {
        let letters = hand.map(String.init)
        guard letters.count >= 2 else { return [] }

        let first = seed % Self.suits.count
        let isSuited = letters.count == 3 && letters[2] == "s"
        let second = isSuited ? first : (first + 1 + seed % 3) % Self.suits.count
        return [(letters[0], Self.suits[first]), (letters[1], Self.suits[second])]
    }

    var body: some View {
        HStack(spacing: -8) {
            ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                PlayingCard(rank: card.rank, suit: card.suit)
                    .rotationEffect(.degrees(index == 0 ? -4 : 4))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Your hand: \(hand)")
    }
}

private struct PlayingCard: View {
    let rank: String
    let suit: String

    private var color: Color {
        suit == "heart" || suit == "diamond" ? Color(hex: "D0162E") : Color(hex: "16181B")
    }

    var body: some View {
        VStack(spacing: 1) {
            Text(rank)
                .font(.system(size: 20, weight: .bold))
            Image(systemName: "suit.\(suit).fill")
                .font(.system(size: 14))
        }
        .foregroundStyle(color)
        .frame(width: 38, height: 54)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
    }
}
