import SwiftUI
import ChartData
import PokerDomain

/// Shows the evidence behind every repair and open question, so the chart owner can rule on them.
/// Rulings are recorded in Data/patches.json, not here.
struct ReviewView: View {
    @EnvironmentObject var rangeManager: RangeManager
    @Environment(\.dismiss) private var dismiss

    private var book: RangeBook? { rangeManager.library?.book }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    if let book {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            sectionTitle("Repairs", count: book.patches.filter { $0.status == .inferred }.count)
                            ForEach(book.patches) { patch in
                                PatchCard(patch: patch)
                            }

                            sectionTitle("Questions", count: book.disputes.filter { $0.status == .open }.count)
                                .padding(.top, 12)
                            ForEach(book.disputes) { dispute in
                                DisputeCard(dispute: dispute)
                            }
                        }
                        .padding(20)
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 760)
        #endif
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Data review")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                Text("Drills stay locked until every item here has a ruling.")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }

            Spacer()

            Button("Done") { dismiss() }
                .buttonStyle(.plain)
                .font(.headline)
                .foregroundColor(.white)
        }
        .padding(20)
    }

    private func sectionTitle(_ title: String, count: Int) -> some View {
        Text("\(title.uppercased()) · \(count)")
            .font(.system(size: 12, weight: .semibold))
            .tracking(1.5)
            .foregroundColor(Theme.textSecondary)
    }
}

private struct PatchCard: View {
    @EnvironmentObject var rangeManager: RangeManager
    let patch: Patch

    private var after: PokerRange? { rangeManager.range(forSpot: patch.spot) }
    private var changedHands: Set<String> { Set(patch.changes.map(\.hand)) }

    var body: some View {
        ReviewCard {
            CardTitle(text: SpotKey(id: patch.spot)?.displayName ?? patch.spot, badge: patch.status == .inferred ? "Needs ruling" : nil)

            Text("CSV line \(patch.sourceLine), labelled \(patch.originalLabel). Changes \(patch.changes.count) cells.")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)

            Text(patch.evidence)
                .font(.subheadline)
                .foregroundColor(Theme.textPrimary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            ReviewGrids {
                LabelledGrid(title: "Before", range: after?.reverting(patch.changes), highlighted: changedHands)
                LabelledGrid(title: "After", range: after, highlighted: changedHands)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(patch.changes, id: \.hand) { change in
                    Text("\(change.hand): \(label(change.was)) → \(label(change.now))")
                        .font(.caption.monospaced())
                        .foregroundColor(Theme.textPrimary.opacity(0.7))
                }
            }
        }
    }

    private func label(_ code: String) -> String {
        OptionKind(code: code)?.label ?? code
    }
}

private struct DisputeCard: View {
    @EnvironmentObject var rangeManager: RangeManager
    let dispute: Dispute

    var body: some View {
        ReviewCard {
            CardTitle(text: dispute.title, badge: dispute.status == .open ? "Needs ruling" : nil)

            Text(dispute.question)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(dispute.detail)
                .font(.subheadline)
                .foregroundColor(Theme.textPrimary.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            if !dispute.spots.isEmpty {
                ReviewGrids {
                    ForEach(dispute.spots, id: \.self) { spot in
                        LabelledGrid(
                            title: SpotKey(id: spot)?.displayName ?? spot,
                            range: rangeManager.range(forSpot: spot),
                            highlighted: Set(dispute.hands ?? [])
                        )
                    }
                }
            }
        }
    }
}

private struct ReviewCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
}

private struct CardTitle: View {
    let text: String
    let badge: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(.headline)
                .foregroundColor(.white)

            Spacer()

            if let badge {
                Text(badge)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.raiseColor)
            }
        }
    }
}

/// Side by side when there's room, stacked on a phone.
private struct ReviewGrids<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
            content
        }
    }
}

private struct LabelledGrid: View {
    let title: String
    let range: PokerRange?
    let highlighted: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.textSecondary)

            PokerGridView(currentRange: range, highlighted: highlighted)
                .aspectRatio(1.0, contentMode: .fit)
        }
    }
}

extension SpotKey {
    var displayName: String {
        let stage = ScenarioType.allCases.indices.contains(line.count) ? ScenarioType.allCases[line.count].label : "\(line.count) actions"
        guard let villain = line.last?.position else { return "\(hero.rawValue) \(stage)" }
        return "\(hero.rawValue) vs \(villain.rawValue) · \(stage)"
    }
}
