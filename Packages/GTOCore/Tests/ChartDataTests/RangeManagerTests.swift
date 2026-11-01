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
            #expect(manager.range(forSpot: spot.id)?.actions.count == 169, "\(spot.id)")
        }
    }

    @Test func rangesUseTheActionsInTheirSpot() async throws {
        let manager = await loaded()
        let open = try #require(manager.range(forSpot: "|LJ"))
        let facing4Bet = try #require(manager.range(forSpot: "LJ:r,BB:r,LJ:r|BB"))
        #expect(open.actions["AA"] == .raise)
        #expect(open.actions["72o"] == .fold)
        #expect(facing4Bet.actions["AA"] == .allIn)
    }

    @Test func spotWithNoDecisionReturnsNil() async {
        let manager = await loaded()
        #expect(manager.range(forSpot: "|BB") == nil)
    }
}
