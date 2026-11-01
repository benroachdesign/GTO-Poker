import SwiftUI
import ChartData
import PokerDomain

struct ExplorerView: View {
    @Bindable var model: ExplorerModel
    var isActive = true // Tabs stay alive when hidden, so a hidden one must not take key presses
    @Environment(RangeManager.self) private var rangeManager

    @State private var showingReview = false
    @FocusState private var isSearching: Bool

    private static let wideWidth: CGFloat = 900
    private static let mediumWidth: CGFloat = 600
    private static let gutter: CGFloat = 16
    private static let gap: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            let size = CGSize(width: geometry.size.width - Self.gutter * 2, height: geometry.size.height)

            VStack(spacing: Self.gap) {
                topBar

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
        .background { keyboardShortcuts }
        .sheet(isPresented: $showingReview) {
            ReviewView()
        }
    }

    // MARK: - Layouts

    private func compactLayout(_ size: CGSize) -> some View {
        let reserved = 32 + 52 + size.width + 78 + Self.gap * 4 + 16
        let panelHeight = min(max(size.height - reserved, 150), 300)

        return ScrollView {
            VStack(spacing: Self.gap) {
                header
                grid
                choiceBar
                compactPanel.frame(height: panelHeight)
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private var compactPanel: some View {
        if let hand = model.selectedHand, let comparison = model.comparison {
            inspector(hand: hand, comparison: comparison, canClose: true)
        } else {
            table
        }
    }

    private func mediumLayout(_ size: CGSize) -> some View {
        let gridSide = min(size.width, size.height * 0.56)

        return VStack(spacing: Self.gap) {
            header
            grid.frame(width: gridSide, height: gridSide)
            choiceBar

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
        let gridSide = min(size.width - sideWidth - Self.gap * 2, size.height - 130)

        return HStack(alignment: .top, spacing: Self.gap * 2) {
            VStack(alignment: .leading, spacing: Self.gap) {
                header
                grid.frame(width: gridSide, height: gridSide)
            }
            .frame(width: gridSide)

            VStack(spacing: Self.gap) {
                table.frame(height: 220)
                choiceBar
                sidePanel
            }
            .frame(width: sideWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.bottom, Self.gap)
    }

    // MARK: - Pieces

    private var topBar: some View {
        HStack(spacing: 8) {
            ActionRail(entries: model.entries, hero: model.key.hero, onSelect: model.go(to:))

            if openReviewCount > 0 {
                Button {
                    showingReview = true
                } label: {
                    Text("Review \(openReviewCount)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Theme.raise, in: Capsule())
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Self.gap) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(model.key.hero.rawValue)
                        .font(.system(size: 28, weight: .bold))
                        .tracking(-0.5)
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.opacity)

                    Text(model.key.situation)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Text(reachText)
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 0)

            HandSearchField(selectedHand: $model.selectedHand, isFocused: $isSearching)
        }
        .frame(height: 52)
    }

    private var grid: some View {
        RangeGridView(cells: model.cells, selected: model.selectedHand) { hand in
            model.selectedHand = model.selectedHand == hand ? nil : hand
        }
    }

    private var choiceBar: some View {
        ChoiceBar(choices: model.choices, shortcutsEnabled: shortcutsEnabled, onChoose: model.choose)
    }

    private var shortcutsEnabled: Bool {
        isActive && !isSearching
    }

    private var table: some View {
        TableView(state: model.table, canTap: model.canTap, onTap: model.tap)
    }

    @ViewBuilder
    private var sidePanel: some View {
        if let hand = model.selectedHand, let comparison = model.comparison {
            inspector(hand: hand, comparison: comparison, canClose: true)
        } else {
            Text("Choose a hand to see how it plays here and across the table.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func inspector(hand: String, comparison: HandComparison, canClose: Bool) -> some View {
        HandInspector(
            hand: hand,
            journey: model.journey,
            comparison: comparison,
            onSelectSpot: model.go(to:),
            onClose: canClose ? { model.selectedHand = nil } : nil
        )
    }

    private var reachText: String {
        model.reachedShare == 1 ? "Every hand is in play" : "\(BetText.share(model.reachedShare)) of hands get here"
    }

    private var openReviewCount: Int {
        rangeManager.library?.book.openReviewCount ?? 0
    }

    // MARK: - Keyboard

    /// Hidden buttons, because a shortcut on a button works wherever focus happens to be.
    /// They step aside during a search, or typing a hand would move around the charts.
    @ViewBuilder
    private var keyboardShortcuts: some View {
        if shortcutsEnabled {
            Group {
                Button("Previous seat") { model.cycle(by: -1) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button("Next seat") { model.cycle(by: 1) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Button("Go back", action: model.goBack)
                    .keyboardShortcut(.upArrow, modifiers: [])
                Button("Clear hand") { model.selectedHand = nil }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
    }
}
