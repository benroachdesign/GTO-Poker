import Testing
import PokerDomain
@testable import ChartData

struct ChartNavigationTests {
    private let library: ChartLibrary

    init() throws {
        library = try ChartLibrary.bundled()
    }

    private func key(_ id: String) throws -> SpotKey {
        try #require(SpotKey(id: id))
    }

    /// Every spot a person could move to in one step.
    private func moves(from spot: SpotKey) -> [SpotKey] {
        var moves = library.choices(at: spot).compactMap(\.destination)
        moves += library.lineEntries(to: spot).map(\.spot)
        moves += library.siblings(of: spot)
        moves += Position.allCases.compactMap { library.destination(tapping: $0, from: spot) }
        return moves
    }

    @Test func startsWithTheFirstSeatToAct() {
        #expect(library.firstSpot?.id == "|LJ")
    }

    @Test func everySpotCanBeReachedByNavigating() throws {
        var visited: Set<SpotKey> = []
        var queue = [try #require(library.firstSpot)]

        while let spot = queue.popLast() {
            guard visited.insert(spot).inserted else { continue }
            queue += moves(from: spot)
        }
        #expect(visited.count == 65)
    }

    @Test func navigationNeverLeavesTheBook() throws {
        for spot in library.book.spots {
            let origin = try #require(spot.key)
            for move in moves(from: origin) {
                #expect(library.spot(move) != nil, "\(origin.id) -> \(move.id)")
            }
        }
    }

    @Test func noSpotIsADeadEnd() throws {
        for spot in library.book.spots {
            let origin = try #require(spot.key)
            #expect(moves(from: origin).contains { $0 != origin }, "\(origin.id)")
        }
    }

    @Test func theBigBlindNeverOpens() {
        #expect(library.siblings(of: SpotKey(line: [], hero: .LJ)).allSatisfy { $0.hero != .BB })
        #expect(library.destination(tapping: .BB, from: SpotKey(line: [], hero: .LJ)) == nil)
    }

    @Test func foldingPassesToTheNextSeatUntilTheyRunOut() throws {
        func fold(_ id: String) throws -> SpotKey? {
            library.choices(at: try key(id)).first { $0.kind == .fold }?.destination
        }
        #expect(try fold("|LJ")?.id == "|HJ")
        #expect(try fold("LJ:r|HJ")?.id == "LJ:r|CO")
        #expect(try fold("|SB") == nil)
        #expect(try fold("LJ:r|BB") == nil)
    }

    @Test func raisingPassesToTheNextPlayerWithADecision() throws {
        func raise(_ id: String, _ kind: OptionKind = .raise) throws -> SpotKey? {
            library.choices(at: try key(id)).first { $0.kind == kind }?.destination
        }
        #expect(try raise("|LJ")?.id == "LJ:r|HJ")
        #expect(try raise("LJ:r|BTN")?.id == "LJ:r,BTN:r|LJ")
        #expect(try raise("LJ:r|BB")?.id == "LJ:r,BB:r|LJ")
        #expect(try raise("LJ:r,BTN:r|LJ")?.id == "LJ:r,BTN:r,LJ:r|BTN")
        #expect(try raise("LJ:r,BTN:r,LJ:r|BTN", .allIn)?.id == "LJ:r,BTN:r,LJ:r,BTN:a|LJ")
    }

    @Test func callingEndsTheLineInThisBook() throws {
        let call = library.choices(at: try key("LJ:r|BB")).first { $0.kind == .call }
        #expect(call != nil)
        #expect(call?.destination == nil)
    }

    @Test func choicesAreNamedForTheirStage() throws {
        func titles(_ id: String) throws -> [String] {
            library.choices(at: try key(id)).map(\.title)
        }
        #expect(try titles("|LJ") == ["Open", "Fold"])
        #expect(try titles("LJ:r|BTN") == ["3-Bet", "Call", "Fold"])
        #expect(try titles("LJ:r,BTN:r|LJ") == ["4-Bet", "Call", "Fold"])
        #expect(try titles("LJ:r,BTN:r,LJ:r|BTN") == ["All-in", "Call", "Fold"])
        #expect(try titles("LJ:r,BTN:r,LJ:r,BTN:a|LJ") == ["Call", "Fold"])
    }

    @Test(arguments: ["|LJ", "LJ:r|BB", "BTN:r,BB:r|BTN", "LJ:r,BTN:r,LJ:r,BTN:a|LJ"])
    func sharesCoverEveryHandThatGotHere(id: String) throws {
        let total = library.choices(at: try key(id)).reduce(0) { $0 + $1.share }
        #expect(abs(total - 1) < 0.000_1)
    }

    @Test func sharesCountOnlyHandsThatReachedTheSpot() throws {
        let open = try #require(library.choices(at: try key("|LJ")).first { $0.kind == .raise })
        #expect(abs(open.share - 0.175) < 0.001)

        // Spots later in the line lean far more aggressive than a share of all 1,326 hands would show
        let facing4Bet = try #require(library.choices(at: try key("LJ:r,BTN:r,LJ:r|BTN")).first { $0.kind == .fold })
        #expect(facing4Bet.share < 0.75)
    }

    @Test func reachedShareShrinksDownTheLine() throws {
        #expect(library.reachedShare(at: try key("|LJ")) == 1)
        #expect(library.reachedShare(at: try key("LJ:r|BTN")) == 1)
        #expect(abs(library.reachedShare(at: try key("LJ:r,BTN:r|LJ")) - 0.175) < 0.001)
    }

    @Test func tappingASeatPrefersThatSeatsOwnDecision() throws {
        #expect(library.destination(tapping: .CO, from: try key("|LJ"))?.id == "|CO")
        #expect(library.destination(tapping: .SB, from: try key("LJ:r|BTN"))?.id == "LJ:r|SB")
    }

    @Test func tappingAnotherSeatSwapsTheOpponent() throws {
        #expect(library.destination(tapping: .CO, from: try key("LJ:r,BTN:r|LJ"))?.id == "LJ:r,CO:r|LJ")
        #expect(library.destination(tapping: .CO, from: try key("LJ:r,BTN:r,LJ:r,BTN:a|LJ"))?.id == "LJ:r,CO:r,LJ:r,CO:a|LJ")
    }

    @Test func tappingTheOpponentGoesBackToTheirTurn() throws {
        #expect(library.destination(tapping: .LJ, from: try key("LJ:r|BTN"))?.id == "|LJ")
        #expect(library.destination(tapping: .BTN, from: try key("LJ:r,BTN:r|LJ"))?.id == "LJ:r|BTN")
    }

    @Test func tappingTheHeroDoesNothing() throws {
        #expect(library.destination(tapping: .LJ, from: try key("|LJ")) == nil)
    }

    @Test func neighboursWrapAroundTheTable() throws {
        #expect(library.neighbour(of: try key("|LJ"), by: 1)?.id == "|HJ")
        #expect(library.neighbour(of: try key("|LJ"), by: -1)?.id == "|SB")
        #expect(library.neighbour(of: try key("LJ:r|BB"), by: 1)?.id == "LJ:r|HJ")
        #expect(library.neighbour(of: try key("LJ:r,BTN:r|LJ"), by: 1) == nil)
    }

    @Test func theLineReadsLikeTheHandPlayedOut() throws {
        let entries = library.lineEntries(to: try key("LJ:r,BTN:r,LJ:r,BTN:a|LJ"))
        #expect(entries.map(\.position) == [.LJ, .BTN, .LJ, .BTN])
        #expect(entries.map(\.title) == ["Open", "3-Bet", "4-Bet", "All-in"])
        #expect(entries.map(\.sizeBB) == [3.5, 10.5, 28.88, 100])
        #expect(entries.first?.spot.id == "|LJ")
    }

    @Test func tableTracksBetsPotAndWhoIsInTheHand() throws {
        let table = library.tableState(at: try key("LJ:r,BTN:r|LJ"))
        let seats = Dictionary(uniqueKeysWithValues: table.seats.map { ($0.position, $0) })

        #expect(table.hero == .LJ)
        #expect(table.pot == 15.5)    // 3.5 + 10.5 + blinds
        #expect(table.toCall == 7)
        #expect(seats[.LJ]?.status == .toAct)
        #expect(seats[.BTN]?.status == .acted(.raise))
        #expect(seats[.BTN]?.bet == 10.5)
        #expect(seats[.HJ]?.status == .folded)
        #expect(seats[.SB]?.status == .folded)
        #expect(seats[.BB]?.bet == 1)
    }

    @Test func playersStillToActAreWaiting() throws {
        let table = library.tableState(at: try key("LJ:r|HJ"))
        let seats = Dictionary(uniqueKeysWithValues: table.seats.map { ($0.position, $0.status) })
        #expect(seats[.CO] == .waiting)
        #expect(seats[.BB] == .waiting)
        #expect(table.toCall == 3.5)
    }

    @Test func aHandsJourneyFollowsTheHerosDecisions() throws {
        let journey = library.journey(of: "AKs", to: try key("LJ:r,BTN:r,LJ:r,BTN:a|LJ"))
        #expect(journey.map(\.title) == ["Opening", "Facing 3-Bet", "Facing All-in"])
        #expect(journey.map(\.action) == [.raise, .raise, .call])
        #expect(journey.last?.isCurrent == true)
    }

    @Test func aJourneyStopsWhereTheHandFolded() throws {
        let journey = library.journey(of: "72o", to: try key("LJ:r,BTN:r|LJ"))
        #expect(journey.map(\.action) == [.fold, nil])
    }

    @Test func comparisonUsesSeatsWhenSeveralCanAct() throws {
        let comparison = library.comparison(of: "A9o", at: try key("|BTN"))
        #expect(comparison.title == "Other seats")
        #expect(comparison.entries.map(\.seat) == [.LJ, .HJ, .CO, .BTN, .SB])
        #expect(comparison.entries.first { $0.isCurrent }?.seat == .BTN)
    }

    @Test func comparisonUsesOpponentsWhenOnlyOneSeatCanAct() throws {
        let comparison = library.comparison(of: "AA", at: try key("LJ:r,BTN:r|LJ"))
        #expect(comparison.title == "Other opponents")
        #expect(comparison.entries.map(\.seat) == [.HJ, .CO, .BTN, .SB, .BB])
        #expect(comparison.entries.allSatisfy { $0.action != nil })
    }

    @Test func comparisonMarksHandsThatNeverGotThere() throws {
        let comparison = library.comparison(of: "72o", at: try key("LJ:r,BTN:r|LJ"))
        #expect(comparison.entries.allSatisfy { $0.action == nil })
    }
}
