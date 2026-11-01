import SwiftUI
import ChartData
import PokerDomain

/// The table, always turned so the player to act sits at the bottom.
/// Seats ride around the rim when it turns, the short way.
struct TableView: View {
    let state: TableState
    let canTap: (Position) -> Bool
    let onTap: (Position) -> Void

    @State private var turn: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let maximumSeatSize: CGFloat = 46

    init(state: TableState, canTap: @escaping (Position) -> Bool, onTap: @escaping (Position) -> Void) {
        self.state = state
        self.canTap = canTap
        self.onTap = onTap
        _turn = State(initialValue: state.hero.index)
    }

    var body: some View {
        GeometryReader { geometry in
            // Side seats sit half the rim apart, so shrink them on a short table rather than let them touch
            let seatSize = min(Self.maximumSeatSize, geometry.size.height * 0.27)
            let rim = CGSize(
                width: geometry.size.width / 2 - seatSize / 2 - 2,
                height: geometry.size.height / 2 - seatSize / 2 - 2
            )

            ZStack {
                Capsule(style: .continuous)
                    .fill(Theme.felt)
                    .overlay(Capsule(style: .continuous).strokeBorder(Theme.hairline))
                    .padding(seatSize / 2 - 6)

                PotLabel(pot: state.pot, toCall: state.toCall)

                ForEach(state.seats) { seat in
                    let phase = Double(seat.position.index - turn)

                    if seat.bet > 0, seat.status != .toAct {
                        Text(seat.bet.formatted(.number.precision(.fractionLength(0...1))))
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                            .modifier(Orbit(phase: phase, radii: rim, inset: seatSize / 2 + 10, sideInset: 12))
                    }

                    Button {
                        onTap(seat.position)
                    } label: {
                        SeatView(seat: seat, isTappable: canTap(seat.position))
                            .frame(width: seatSize, height: seatSize)
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(!canTap(seat.position))
                    .modifier(Orbit(phase: phase, radii: rim))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onChange(of: state.hero) { previous, hero in
            // Always in -3...2, so the table never goes the long way round
            let steps = (hero.index - previous.index + 9) % 6 - 3
            withAnimation(reduceMotion ? nil : Theme.motion) {
                turn += steps
            }
        }
    }
}

/// Moves a centred view onto an ellipse, clockwise from the bottom. Animating the
/// phase carries it along the rim, where animating a position would cut across the table.
/// An inset pulls it that far in toward the middle, so a bet can sit just in front of its seat,
/// with extra room at the sides of the table because numbers are wider than they are tall.
private struct Orbit: GeometryEffect {
    var phase: Double
    let radii: CGSize
    var inset: CGFloat = 0
    var sideInset: CGFloat = 0

    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let angle = phase * .pi / 3
        let x = -radii.width * sin(angle)
        let y = radii.height * cos(angle)
        let distance = hypot(x, y)
        let pulledIn = inset + sideInset * abs(sin(angle))
        let scale = distance > 0 ? max(distance - pulledIn, 0) / distance : 0
        return ProjectionTransform(CGAffineTransform(translationX: x * scale, y: y * scale))
    }
}

private struct PotLabel: View {
    let pot: Double
    let toCall: Double

    var body: some View {
        VStack(spacing: 1) {
            Text("POT \(BetText.size(pot))")
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(Theme.textPrimary)
            if toCall > 0 {
                Text("\(BetText.size(toCall)) to call")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .monospacedDigit()
    }
}

private struct SeatView: View {
    let seat: TableSeat
    let isTappable: Bool

    private var fill: Color {
        switch seat.status {
        case .toAct: return .white
        case .acted(let action): return Theme.color(for: action)
        case .waiting: return Color(hex: "3A3F45")
        case .folded: return Theme.background
        }
    }

    private var text: Color {
        switch seat.status {
        case .toAct: return .black
        case .acted, .waiting: return .white
        case .folded: return isTappable ? Theme.textSecondary : Theme.textTertiary
        }
    }

    private var border: Color {
        seat.status == .folded ? Theme.hairline : .clear
    }

    var body: some View {
        Circle()
            .fill(fill)
            .overlay(Circle().strokeBorder(border))
            .overlay {
                Text(seat.position.rawValue)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(text)
            }
            .overlay(alignment: .topTrailing) {
                if seat.position == .BTN {
                    Text("D")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.black.opacity(0.8))
                        .frame(width: 16, height: 16)
                        .background(Color(hex: "FF9900"), in: Circle())
                        .offset(x: 2, y: -2)
                }
            }
            .accessibilityLabel(seat.position.rawValue)
            .accessibilityValue(accessibilityStatus)
    }

    private var accessibilityStatus: String {
        switch seat.status {
        case .toAct: return "To act"
        case .acted(let action): return action.label
        case .waiting: return "Yet to act"
        case .folded: return "Folded"
        }
    }
}
