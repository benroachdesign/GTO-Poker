import Testing
@testable import PokerDomain

struct HandGridTests {
    @Test func namesFollowTheGridConvention() {
        #expect(HandGrid.getHandName(row: 0, col: 0) == "AA")
        #expect(HandGrid.getHandName(row: 0, col: 1) == "AKs")
        #expect(HandGrid.getHandName(row: 1, col: 0) == "AKo")
        #expect(HandGrid.getHandName(row: 12, col: 12) == "22")
    }

    @Test func gridHolds169UniqueHands() {
        let hands = allHands()
        #expect(hands.count == 169)
        #expect(Set(hands).count == 169)
    }

    @Test func combosCoverEveryStartingHand() {
        let total = allHands().reduce(0.0) { $0 + HandGrid.getCombos(for: $1) }
        #expect(total == 1326)
    }

    @Test func coordinatesInvertHandNames() {
        for row in 0..<13 {
            for col in 0..<13 {
                let cell = HandGrid.coordinates(of: HandGrid.getHandName(row: row, col: col))
                #expect(cell?.row == row && cell?.col == col)
            }
        }
    }

    @Test func coordinatesRejectHandsThatDontExist() {
        #expect(HandGrid.coordinates(of: "AAs") == nil)
        #expect(HandGrid.coordinates(of: "AK") == nil)
        #expect(HandGrid.coordinates(of: "1Ks") == nil)
    }

    private func allHands() -> [String] {
        HandGrid.allHands
    }
}

struct SpotKeyTests {
    private func key(_ id: String) -> SpotKey? { SpotKey(id: id) }

    @Test func idsRoundTrip() {
        for id in ["|LJ", "LJ:r|BTN", "LJ:r,BTN:r,LJ:r,BTN:r|LJ", "LJ:r@2.5,BTN:c|BB"] {
            #expect(key(id)?.id == id)
        }
    }

    @Test func malformedIdsAreRejected() {
        for id in ["", "LJ", "XX:r|LJ", "LJ:z|BTN", "LJ:r|XX", "LJ:r,|BTN", "LJ:r|BTN|BB"] {
            #expect(key(id) == nil, "\(id)")
        }
    }

    @Test func scenariosBuildHeadsUpLines() {
        #expect(SpotKey(scenario: .rfi, hero: .LJ, villain: nil)?.id == "|LJ")
        #expect(SpotKey(scenario: .vsRaise, hero: .BTN, villain: .LJ)?.id == "LJ:r|BTN")
        #expect(SpotKey(scenario: .vs3bet, hero: .LJ, villain: .BTN)?.id == "LJ:r,BTN:r|LJ")
        #expect(SpotKey(scenario: .vs4bet, hero: .BTN, villain: .LJ)?.id == "LJ:r,BTN:r,LJ:r|BTN")
        #expect(SpotKey(scenario: .vs5bet, hero: .LJ, villain: .BTN)?.id == "LJ:r,BTN:r,LJ:r,BTN:a|LJ")
        #expect(SpotKey(scenario: .vs3bet, hero: .LJ, villain: nil) == nil)
    }

    @Test func realLinesArePlayable() {
        for id in ["|LJ", "|SB", "LJ:r|BB", "LJ:r,BTN:r|LJ", "LJ:r,BTN:r,LJ:r|BTN", "SB:r,BB:r|SB"] {
            #expect(key(id)?.isPlayable == true, "\(id)")
        }
    }

    @Test func multiwayLinesFitWithoutAnyChange() {
        let coldFourBet = key("LJ:r,HJ:r|BTN")
        let squeeze = key("LJ:r,CO:c|BTN")
        let limp = key("SB:c|BB")
        #expect(coldFourBet?.isPlayable == true)
        #expect(squeeze?.isPlayable == true)
        #expect(limp?.isPlayable == true)
    }

    @Test func impossibleLinesAreRejected() {
        let impossible = [
            "|BB",               // Everyone folded to the BB, so there's no decision
            "LJ:r|LJ",           // Everyone folded to the raiser
            "LJ:r,BTN:c|LJ",     // A call closes the action on the raiser
            "BTN:r,LJ:r|LJ",     // LJ acts before the BTN
            "LJ:r,BTN:r|HJ",     // HJ was skipped, so they folded
            "LJ:r,LJ:r|BTN",     // LJ can't raise their own raise
            "LJ:r,BTN:r,CO:r|LJ" // CO was skipped, so they folded
        ]
        for id in impossible {
            #expect(key(id)?.isPlayable == false, "\(id)")
        }
    }

    @Test func decisionsPointAtEarlierSpots() throws {
        let spot = try #require(key("LJ:r,BTN:r,LJ:r|BTN"))
        #expect(spot.decisions.map(\.spot.id) == ["|LJ", "LJ:r|BTN", "LJ:r,BTN:r|LJ"])
        #expect(spot.heroPreviousDecision?.spot.id == "LJ:r|BTN")
        #expect(key("LJ:r|BTN")?.heroPreviousDecision == nil)
    }
}

struct PositionTests {
    @Test func fromIndexWrapsBothWays() {
        #expect(Position.fromIndex(6) == .SB)
        #expect(Position.fromIndex(-1) == .BTN)
    }

    @Test func preflopOrderStartsAtLJAndEndsAtBB() {
        let order = Position.allCases.sorted { $0.preflopOrder < $1.preflopOrder }
        #expect(order == [.LJ, .HJ, .CO, .BTN, .SB, .BB])
        #expect(order == Position.preflopSequence)
    }

    @Test func positionIsAboutWhoActsLastAfterTheFlop() {
        #expect(Position.BTN.isInPosition(against: .CO))
        #expect(Position.BB.isInPosition(against: .SB))
        #expect(Position.HJ.isInPosition(against: .LJ))
        #expect(!Position.CO.isInPosition(against: .BTN))
        #expect(!Position.BB.isInPosition(against: .LJ))
        #expect(!Position.SB.isInPosition(against: .BTN))
    }
}
