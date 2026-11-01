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

    private func allHands() -> [String] {
        (0..<13).flatMap { row in
            (0..<13).map { col in HandGrid.getHandName(row: row, col: col) }
        }
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
    }
}
