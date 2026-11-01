import Testing
@testable import ChartData

@MainActor
struct RangeManagerTests {
    @Test func loadsAllSixtyFiveSpots() {
        #expect(RangeManager().rangesByKey.count == 65)
    }

    @Test func everySpotHasAllHands() {
        for range in RangeManager().rangesByKey.values {
            #expect(range.ranges.count == 169, "\(range.id)")
        }
    }

    @Test func statsAddUpToOneHundred() throws {
        let range = try #require(RangeManager().getRange(scenario: "Open", hero: "LJ", villain: nil))
        let stats = range.stats
        #expect(abs(stats.raise + stats.call + stats.fold - 100) < 0.001)
        #expect(abs(stats.raise - 17.5) < 0.1)
    }

    @Test func lookupIgnoresCase() {
        let manager = RangeManager()
        #expect(manager.getRange(scenario: "VS 3BET", hero: "btn", villain: "bb") != nil)
    }

    @Test func missingSpotReturnsNil() {
        #expect(RangeManager().getRange(scenario: "Open", hero: "BB", villain: nil) == nil)
    }
}
