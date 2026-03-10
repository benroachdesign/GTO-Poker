import SwiftUI

struct ContentView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var rangeManager: RangeManager
    
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // MARK: - Header
                HStack {
                    Spacer()

                    VStack(spacing: 2) {
                        Text(headerTitle)
                            .font(.system(size: 18, weight: .heavy))
                            .tracking(2)
                            .foregroundColor(.white)
                            .opacity(0.9)

                        Text("GTO POKER")
                            .font(.system(size: 10, weight: .medium))
                            .tracking(3)
                            .foregroundColor(.white.opacity(0.4))
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 10)
                
                // MARK: - Grid
                PokerGridView(currentRange: currentRange)
                    .padding(20)
                    .aspectRatio(1.0, contentMode: .fit)
                
                // MARK: - Legend
                HStack(spacing: 20) {
                    LegendItem(color: Theme.raiseColor, label: "Raise", percent: currentStats.raise)
                    LegendItem(color: Theme.callColor, label: "Call", percent: currentStats.call)
                    LegendItem(color: Theme.gridEmpty, label: "Fold", percent: currentStats.fold)
                }
                .animation(.easeInOut(duration: 0.2), value: currentStats.raise)
                .padding(.bottom, 10)
                
                Spacer()
                
                // MARK: - Table
                PokerTableView()
                    .padding(.horizontal, 20)
                
                // MARK: - Footer Buttons
                HStack(spacing: 20) {
                    Button(action: {
                        withAnimation {
                            gameState.previousHand()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                            Text(gameState.previousHeroPosition.rawValue)
                                .font(.headline)
                        }
                        .foregroundColor(.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(30)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        withAnimation {
                            gameState.rotateDealer()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Text(gameState.nextHeroPosition.rawValue)
                                .font(.headline)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(30)
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
        }
    }
    
    // Computed Properties
    var currentRange: PokerRange? {
        let heroPos = gameState.heroPosition.rawValue
        var villainPos: String? = nil
        let scenario = gameState.activeScenario.rawValue

        if let vSeat = gameState.selectedVillainSeat {
            let vPosName = gameState.getPosition(forSeat: vSeat).rawValue
            villainPos = vPosName
        }
        return rangeManager.getRange(scenario: scenario, hero: heroPos, villain: villainPos)
    }
    
    var currentStats: RangeStats {
        return currentRange?.stats ?? RangeStats(raise: 0, call: 0, fold: 0)
    }
    
    var headerTitle: String {
        let hero = gameState.heroPosition.rawValue
        if let vSeat = gameState.selectedVillainSeat {
            let villain = gameState.getPosition(forSeat: vSeat).rawValue
            return "\(hero) vs \(villain)"
        } else {
            return "\(hero) RFI"
        }
    }
}

struct LegendItem: View {
    let color: Color
    let label: String
    let percent: Double
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(label) \(Int(percent.rounded()))%")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.2), value: percent)
        }
    }
}
