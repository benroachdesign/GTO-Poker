import Foundation
import SwiftUI
import PokerDomain

@MainActor
final class GameState: ObservableObject {
    // 1-Based Seat Integers (1 to 6)
    // Hero is always seated physically at Seat 1.
    
    @Published var dealerSeat: Int = 1 // 1-6
    @Published var selectedVillainSeat: Int? = nil // Nil = Hero only (Open), 2-6 = Villain
    @Published var activeScenario: ScenarioType = .rfi
    
    // Computed Properties
    
    var heroPosition: Position {
        return getPosition(forSeat: 1)
    }
    
    /// Get the logical position of any physical seat (1-6)
    func getPosition(forSeat seat: Int) -> Position {
        let stepsFromBtn = seat - dealerSeat
        let posIndex = (5 + stepsFromBtn)
        return Position.fromIndex(posIndex)
    }
    
    /// Get the physical seat (1-6) for a logical position
    func getSeat(for position: Position) -> Int {
        // Inverse of getPosition
        // posIndex = 5 + seat - dealerSeat
        // seat = posIndex - 5 + dealerSeat
        let val = position.index - 5 + dealerSeat
        // Normalize to 1-6
        let normalized = ((val - 1) % 6 + 6) % 6 + 1
        return normalized
    }
    
    func rotateDealer() {
        if dealerSeat >= 6 {
            dealerSeat = 1
        } else {
            dealerSeat += 1
        }
        // Reset state on hand change
        selectedVillainSeat = nil
        activeScenario = .rfi
    }
    
    func previousHand() {
        if dealerSeat <= 1 {
            dealerSeat = 6
        } else {
            dealerSeat -= 1
        }
        // Reset state
        selectedVillainSeat = nil
        activeScenario = .rfi
    }
    
    func selectVillain(_ seat: Int) {
        if seat == 1 {
            // Clicking Hero -> Reset to Open/RFI
            selectedVillainSeat = nil
            activeScenario = .rfi
        } else {
            let villainPos = getPosition(forSeat: seat)
            let valid = getValidScenarios(hero: heroPosition, villain: villainPos)
            
            if selectedVillainSeat == seat {
                // Cycle Logic
                cycleScenario()
            } else {
                // New Villain -> Default to first valid scenario
                selectedVillainSeat = seat
                activeScenario = valid.first ?? .vsRaise
            }
        }
    }
    
    func cycleScenario() {
        guard let vSeat = selectedVillainSeat else { return }
        let villain = getPosition(forSeat: vSeat)
        let valid = getValidScenarios(hero: heroPosition, villain: villain)
        
        if let currentIndex = valid.firstIndex(of: activeScenario) {
            let nextIndex = (currentIndex + 1) % valid.count
            activeScenario = valid[nextIndex]
        } else {
            // Current scenario invalid? Reset to first
            activeScenario = valid.first ?? .vsRaise
        }
    }
    
    func getValidScenarios(hero: Position, villain: Position) -> [ScenarioType] {
        if villain.preflopOrder < hero.preflopOrder {
            // Villain acts BEFORE Hero (e.g. UTG vs BTN)
            // They can Open (we face raise) OR They can 4-bet (we 3-bet)
            return [.vsRaise, .vs4bet]
        } else {
            // Villain acts AFTER Hero (e.g. BTN vs BB)
            // We Open (they 3-bet) OR We 4-bet (they 5-bet)
            return [.vs3bet, .vs5bet]
        }
    }
    
    var nextHeroPosition: Position {
        let nextDealer = dealerSeat >= 6 ? 1 : dealerSeat + 1
        return Position.fromIndex(5 + (1 - nextDealer))
    }

    var previousHeroPosition: Position {
        let prevDealer = dealerSeat <= 1 ? 6 : dealerSeat - 1
        return Position.fromIndex(5 + (1 - prevDealer))
    }

    /// Scenarios available for the currently selected villain (empty if none selected)
    var validScenariosForSelected: [ScenarioType] {
        guard let vSeat = selectedVillainSeat else { return [] }
        return getValidScenarios(hero: heroPosition, villain: getPosition(forSeat: vSeat))
    }

    /// Primary label shown on the table — scenario type is the most actionable info
    var currentScenarioDescription: String {
        if selectedVillainSeat != nil {
            return activeScenario.label
        } else {
            return "Opening"
        }
    }

    /// Secondary label — positional context
    var currentScenarioSubtitle: String {
        let heroPos = heroPosition.rawValue
        if let vSeat = selectedVillainSeat {
            let villainPos = getPosition(forSeat: vSeat).rawValue
            return "\(heroPos) vs \(villainPos)"
        } else {
            return "\(heroPos) RFI"
        }
    }
}
