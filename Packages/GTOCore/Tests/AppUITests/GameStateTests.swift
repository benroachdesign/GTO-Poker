import Testing
import ChartData
import PokerDomain
@testable import AppUI

@MainActor
struct GameStateTests {
    @Test func seatAndPositionAreInverses() {
        let state = GameState()
        for dealer in 1...6 {
            state.dealerSeat = dealer
            for seat in 1...6 {
                #expect(state.getSeat(for: state.getPosition(forSeat: seat)) == seat)
            }
        }
    }

    @Test func dealerSeatIsAlwaysTheButton() {
        let state = GameState()
        for dealer in 1...6 {
            state.dealerSeat = dealer
            #expect(state.getPosition(forSeat: dealer) == .BTN)
        }
    }

    @Test func rotatingWrapsAndResetsTheHand() {
        let state = GameState()
        state.dealerSeat = 6
        state.selectVillain(3)
        state.rotateDealer()
        #expect(state.dealerSeat == 1)
        #expect(state.selectedVillainSeat == nil)
        #expect(state.activeScenario == .rfi)

        state.previousHand()
        #expect(state.dealerSeat == 6)
    }

    @Test func nextAndPreviousLabelsMatchWhereTheHeroLands() {
        let state = GameState()
        for dealer in 1...6 {
            state.dealerSeat = dealer
            let next = state.nextHeroPosition
            let previous = state.previousHeroPosition

            state.rotateDealer()
            #expect(state.heroPosition == next)

            state.dealerSeat = dealer
            state.previousHand()
            #expect(state.heroPosition == previous)
        }
    }

    @Test func selectingTheSameVillainCyclesScenarios() {
        let state = GameState()
        state.dealerSeat = 4 // Hero is LJ, so every villain acts after them
        state.selectVillain(2)
        #expect(state.activeScenario == .vs3bet)
        state.selectVillain(2)
        #expect(state.activeScenario == .vs5bet)
        state.selectVillain(2)
        #expect(state.activeScenario == .vs3bet)
    }

    @Test func selectingTheHeroGoesBackToOpening() {
        let state = GameState()
        state.selectVillain(2)
        state.selectVillain(1)
        #expect(state.selectedVillainSeat == nil)
        #expect(state.activeScenario == .rfi)
    }

    @Test func everySpotTheTableCanReachHasARange() async {
        let state = GameState()
        let manager = RangeManager()
        await manager.load()

        for dealer in 1...6 {
            state.dealerSeat = dealer
            let hero = state.heroPosition

            if hero != .BB {
                #expect(manager.getRange(scenario: .rfi, hero: hero, villain: nil) != nil)
            }

            for seat in 2...6 {
                let villain = state.getPosition(forSeat: seat)
                for scenario in state.getValidScenarios(hero: hero, villain: villain) {
                    let range = manager.getRange(scenario: scenario, hero: hero, villain: villain)
                    #expect(range != nil, "\(scenario.rawValue) \(hero.rawValue) v \(villain.rawValue)")
                }
            }
        }
    }
}
