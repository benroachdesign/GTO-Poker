import SwiftUI
import ChartData
import PokerDomain

enum CellState: Equatable {
    case action(OptionKind)
    case unreached // The hero already folded this hand earlier on the line
}

struct RangeGridView: View {
    let cells: [String: CellState]
    var selected: String? = nil
    var highlighted: Set<String> = []
    var onSelect: ((String) -> Void)? = nil

    private static let spacing: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            let cellSize = (geometry.size.width - Self.spacing * 12) / 13

            VStack(spacing: Self.spacing) {
                ForEach(0..<13, id: \.self) { row in
                    HStack(spacing: Self.spacing) {
                        ForEach(0..<13, id: \.self) { col in
                            let hand = HandGrid.getHandName(row: row, col: col)
                            GridCell(
                                hand: hand,
                                state: cells[hand] ?? .unreached,
                                size: cellSize,
                                isSelected: hand == selected,
                                isHighlighted: highlighted.contains(hand)
                            )
                            .onTapGesture { onSelect?(hand) }
                        }
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct GridCell: View {
    let hand: String
    let state: CellState
    let size: CGFloat
    let isSelected: Bool
    let isHighlighted: Bool

    private var fill: Color {
        switch state {
        case .action(let action): return Theme.color(for: action)
        case .unreached: return .clear
        }
    }

    private var textColor: Color {
        switch state {
        case .action(.fold): return .white.opacity(0.4)
        case .action: return .white
        case .unreached: return .white.opacity(0.16)
        }
    }

    private var description: String {
        switch state {
        case .action(let action): return "\(hand): \(action.label)"
        case .unreached: return "\(hand): already folded"
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)

        shape
            .fill(fill)
            .frame(width: size, height: size)
            .overlay {
                Text(hand)
                    .font(.system(size: size * 0.33, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(textColor)
            }
            .overlay {
                if isSelected {
                    shape.strokeBorder(Color.white, lineWidth: max(2, size * 0.09))
                } else if isHighlighted {
                    shape.strokeBorder(Color.white.opacity(0.8), lineWidth: max(1, size * 0.06))
                }
            }
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: state)
            .help(description)
            .accessibilityElement()
            .accessibilityLabel(description)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
