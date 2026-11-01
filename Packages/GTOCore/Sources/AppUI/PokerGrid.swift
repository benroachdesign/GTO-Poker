import SwiftUI
import ChartData
import PokerDomain

struct PokerGridView: View {
    let currentRange: PokerRange?

    private let ranks = HandGrid.ranks

    var body: some View {
        GeometryReader { geo in
            let labelSize: CGFloat = 14
            let spacing: CGFloat = 3
            let availableWidth = geo.size.width - labelSize - spacing
            let totalSpacing = spacing * 12
            let cellSize = (availableWidth - totalSpacing) / 13

            VStack(spacing: spacing) {
                // Top rank labels
                HStack(spacing: spacing) {
                    Color.clear.frame(width: labelSize, height: labelSize) // corner spacer
                    ForEach(ranks, id: \.self) { rank in
                        Text(rank)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.3))
                            .frame(width: cellSize)
                    }
                }

                ZStack {
                    // Left rank labels + grid rows
                    HStack(alignment: .top, spacing: spacing) {
                        VStack(spacing: spacing) {
                            ForEach(ranks, id: \.self) { rank in
                                Text(rank)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.white.opacity(0.3))
                                    .frame(width: labelSize, height: cellSize)
                            }
                        }

                        VStack(spacing: spacing) {
                            ForEach(0..<13, id: \.self) { row in
                                HStack(spacing: spacing) {
                                    ForEach(0..<13, id: \.self) { col in
                                        let hand = HandGrid.getHandName(row: row, col: col)
                                        let action = currentRange?.ranges[hand]
                                        GridCell(hand: hand, action: action, size: cellSize)
                                    }
                                }
                            }
                        }
                    }

                    if currentRange == nil {
                        VStack(spacing: 8) {
                            Image(systemName: "questionmark.square.dashed")
                                .font(.system(size: 36))
                                .foregroundColor(.white.opacity(0.3))
                            Text("No range data for this spot")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                }
            }
        }
    }
    
}

struct GridCell: View {
    let hand: String
    let action: String?
    let size: CGFloat

    var fillColor: Color {
        switch action {
        case "Raise", "All-in": return Theme.raiseColor
        case "Call": return Theme.callColor
        default: return Theme.gridEmpty
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.18)
            .fill(fillColor)
            .frame(width: size, height: size)
            .overlay(
                Text(hand)
                    .font(.system(size: size * 0.35, weight: .bold))
                    .foregroundColor(action == "Fold" || action == nil ? Color.white.opacity(0.25) : Color.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
            )
            .animation(.easeInOut(duration: 0.2), value: action)
            .help("\(hand): \(action ?? "Fold")")
    }
}
