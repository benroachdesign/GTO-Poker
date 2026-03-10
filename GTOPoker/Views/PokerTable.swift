import SwiftUI

struct PokerTableView: View {
    @EnvironmentObject var gameState: GameState
    
    let seatCoordinates: [(x: CGFloat, y: CGFloat)] = [
        (0.5, 0.90), // S1
        (0.12, 0.70), // S2
        (0.12, 0.30), // S3
        (0.5, 0.10), // S4
        (0.88, 0.30), // S5
        (0.88, 0.70)  // S6
    ]
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Table Surface
                RoundedRectangle(cornerRadius: 60)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color(hex: "4CAF50"), Color(hex: "2E7D32")]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                    .padding(20)
                
                // Center Info Text
                VStack(spacing: 4) {
                    Text(gameState.currentScenarioDescription)
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(.white.opacity(0.9))
                    
                    Text(gameState.currentScenarioSubtitle)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .textCase(.uppercase)
                }
                .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                
                // Seats
                // Iterate by Position so that the View identity persists (e.g. "BTN" view)
                // and animates to the new seat coordinate.
                ForEach(Position.allCases, id: \.self) { position in
                    let seatNum = gameState.getSeat(for: position)
                    let coord = seatCoordinates[seatNum - 1]
                    
                    SeatView(seatNumber: seatNum)
                        .position(x: geo.size.width * coord.x, y: geo.size.height * coord.y)
                        .animation(.spring(response: 0.6, dampingFraction: 0.7, blendDuration: 0), value: gameState.dealerSeat)
                }
            }
        }
        .frame(minHeight: 180, maxHeight: 260)
    }
}

struct SeatView: View {
    @EnvironmentObject var gameState: GameState
    let seatNumber: Int
    @State private var pulse = false
    
    var positionName: String {
        return gameState.getPosition(forSeat: seatNumber).rawValue
    }
    
    var isSelected: Bool {
        return gameState.selectedVillainSeat == seatNumber
    }
    
    var isHero: Bool {
        return seatNumber == 1
    }
    
    var isDealer: Bool {
        return gameState.dealerSeat == seatNumber
    }
    
    // Pulse eligibility: Not Hero, Not Selected, and we have a dealer (game active)
    var shouldPulse: Bool {
        !isHero && !isSelected
    }
    
    // Badge for click cycling (e.g., "3B")
    var stateBadge: String? {
        if isSelected {
            return gameState.activeScenario.badge
        }
        return nil
    }
    
    var body: some View {
        Button(action: {
            withAnimation {
                gameState.selectVillain(seatNumber)
            }
        }) {
            VStack(spacing: 4) {
                ZStack {
                    // Pulse Animation Layer
                    if shouldPulse {
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                            .frame(width: 48, height: 48)
                            .scaleEffect(pulse ? 1.15 : 1.0)
                            .opacity(pulse ? 0.0 : 1.0)
                            .onAppear {
                                pulse = false
                                withAnimation(Animation.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
                                    pulse = true
                                }
                            }
                    }

                    // Seat Base
                    ZStack {
                        Circle()
                            .fill(fillColor)

                        if isDealer && !isSelected && !isHero {
                            Circle()
                                .strokeBorder(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 4, dash: [5, 5]))
                                .padding(4)
                            Circle()
                                .strokeBorder(Color.black.opacity(0.3), lineWidth: 1)
                                .padding(8)
                        } else if isSelected {
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                        }
                    }
                    .frame(width: 48, height: 48)
                    .shadow(radius: 2)

                    // Position Text
                    Text(positionName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(textColor)

                    // Badge Overlay (scenario badge OR dealer-on-hero "D" badge)
                    if let badge = stateBadge ?? (isHero && isDealer ? "D" : nil) {
                        GeometryReader { g in
                            ZStack {
                                Circle()
                                    .fill(isHero && isDealer && stateBadge == nil ? Color(hex: "FF9900") : Color.red)
                                Text(badge)
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .frame(width: 18, height: 18)
                            .position(x: g.size.width * 0.85, y: g.size.height * 0.15)
                        }
                        .frame(width: 48, height: 48)
                    }
                }

                // Scenario pip dots below selected villain seat
                if isSelected {
                    HStack(spacing: 4) {
                        ForEach(gameState.validScenariosForSelected, id: \.self) { scenario in
                            Circle()
                                .fill(scenario == gameState.activeScenario ? Color.white : Color.white.opacity(0.3))
                                .frame(width: 5, height: 5)
                        }
                    }
                } else {
                    Color.clear.frame(height: 9)
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    var fillColor: Color {
        if isSelected { return Theme.villainSeat }
        if isHero { return Theme.heroSeat }       // Hero always white, even when dealer
        if isDealer { return Color(hex: "FF9900") }
        return Theme.neutralSeat
    }

    var textColor: Color {
        if isSelected { return Theme.villainText }
        if isHero { return Theme.heroText }
        if isDealer { return .black.opacity(0.8) }
        return Color.black.opacity(0.6)
    }
}
