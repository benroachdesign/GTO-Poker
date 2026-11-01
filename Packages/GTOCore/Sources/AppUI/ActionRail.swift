import SwiftUI
import ChartData
import PokerDomain

/// The hand so far, as one line you can step back along.
struct ActionRail: View {
    let entries: [LineEntry]
    let hero: Position
    let onSelect: (SpotKey) -> Void

    @State private var isScrolled = false

    private static let heroID = "hero"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(entries) { entry in
                        Button {
                            onSelect(entry.spot)
                        } label: {
                            RailChip(position: entry.position.rawValue, detail: detail(for: entry), dot: Theme.color(for: entry.kind))
                        }
                        .buttonStyle(PressableStyle())

                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }

                    RailChip(position: hero.rawValue, detail: "to act", dot: .white, isCurrent: true)
                        .id(Self.heroID)
                }
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.x > 1 } action: { _, scrolled in
                isScrolled = scrolled
            }
            .mask {
                // Only fades once there's something scrolled away to hint at
                HStack(spacing: 0) {
                    LinearGradient(colors: [isScrolled ? .clear : .black, .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 24)
                    Color.black
                }
            }
            .onAppear {
                proxy.scrollTo(Self.heroID, anchor: .trailing)
            }
            .onChange(of: entries.map(\.id)) {
                withAnimation(Theme.motion) {
                    proxy.scrollTo(Self.heroID, anchor: .trailing)
                }
            }
        }
    }

    private func detail(for entry: LineEntry) -> String {
        guard let size = entry.sizeBB, entry.kind != .allIn else { return entry.title }
        return "\(entry.title) \(BetText.size(size))"
    }
}

private struct RailChip: View {
    let position: String
    let detail: String
    let dot: Color
    var isCurrent = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dot)
                .frame(width: 6, height: 6)
            Text(position)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(detail)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(isCurrent ? Theme.surfaceRaised : Theme.surface, in: Capsule())
    }
}
