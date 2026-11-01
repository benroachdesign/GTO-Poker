import Testing
import PokerDomain
@testable import ChartData

@MainActor
struct RangeManagerTests {
    private func loaded() async -> RangeManager {
        let manager = RangeManager()
        await manager.load()
        return manager
    }

    @Test func loadsAllSixtyFiveSpots() async {
        let manager = await loaded()
        #expect(manager.library?.book.spots.count == 65)
        #expect(manager.loadError == nil)
    }

    @Test func everySpotHasAllHands() async throws {
        let manager = await loaded()
        let library = try #require(manager.library)
        for spot in library.book.spots {
            #expect(manager.range(forSpot: spot.id)?.ranges.count == 169, "\(spot.id)")
        }
    }

    @Test func statsAddUpToOneHundred() async throws {
        let manager = await loaded()
        let range = try #require(manager.getRange(scenario: .rfi, hero: .LJ, villain: nil))
        let stats = range.stats
        #expect(abs(stats.raise + stats.call + stats.fold - 100) < 0.001)
        #expect(abs(stats.raise - 17.5) < 0.1)
    }

    @Test func scenariosFindTheirSpot() async {
        let manager = await loaded()
        #expect(manager.getRange(scenario: .vs3bet, hero: .BTN, villain: .BB)?.id == "BTN:r,BB:r|BTN")
    }

    @Test func spotsFacingA4BetCallTheirAggressiveActionAllIn() async throws {
        let manager = await loaded()
        let open = try #require(manager.getRange(scenario: .rfi, hero: .LJ, villain: nil))
        let facing4Bet = try #require(manager.getRange(scenario: .vs4bet, hero: .BB, villain: .LJ))
        #expect(open.aggressiveLabel == "Raise")
        #expect(facing4Bet.aggressiveLabel == "All-in")
        #expect(facing4Bet.stats.raise > 0)
    }

    @Test func spotWithNoDecisionReturnsNil() async {
        let manager = await loaded()
        #expect(manager.getRange(scenario: .rfi, hero: .BB, villain: nil) == nil)
    }
}
