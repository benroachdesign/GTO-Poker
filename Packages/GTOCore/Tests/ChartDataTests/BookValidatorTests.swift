import Foundation
import Testing
import PokerDomain
@testable import ChartData

struct BookValidatorTests {
    private func book() throws -> RangeBook {
        try ChartLibrary.bundled().book
    }

    private func errors(_ book: RangeBook) -> [Finding] {
        BookValidator.validate(book).filter { $0.severity == .error }
    }

    private func index(of id: String, in book: RangeBook) throws -> Int {
        try #require(book.spots.firstIndex { $0.id == id })
    }

    @Test func bundledBookHasNoErrors() throws {
        #expect(try errors(book()).isEmpty)
    }

    @Test func gridOfTheWrongShapeIsAnError() throws {
        var book = try book()
        book.spots[0].grid.removeLast()
        #expect(errors(book).contains { $0.rule == .structure })
    }

    @Test func cellUsingAnUnknownOptionIsAnError() throws {
        var book = try book()
        let open = try index(of: "|LJ", in: book)
        book.spots[open].grid[0] = "C" + book.spots[open].grid[0].dropFirst()
        #expect(errors(book).contains { $0.rule == .structure && $0.hand == "AA" })
    }

    @Test func missingSpotIsACoverageError() throws {
        var book = try book()
        book.spots.remove(at: try index(of: "LJ:r|HJ", in: book))
        #expect(errors(book).contains { $0.rule == .coverage && $0.spot == "LJ:r|HJ" })
    }

    @Test func repeatedSpotIsAnError() throws {
        var book = try book()
        book.spots.append(book.spots[0])
        #expect(errors(book).contains { $0.rule == .duplicateSpot })
    }

    @Test func lineThatCantHappenIsAReplayError() throws {
        var book = try book()
        book.spots[0].id = "LJ:r|LJ"
        #expect(errors(book).contains { $0.rule == .replay && $0.spot == "LJ:r|LJ" })
    }

    @Test func handTheHeroAlreadyFoldedCantContinue() throws {
        var book = try book()
        let open = try index(of: "|LJ", in: book)
        // AA stops opening, but every later LJ spot still continues with it
        book.spots[open].grid[0] = "F" + book.spots[open].grid[0].dropFirst()
        #expect(errors(book).contains { $0.rule == .heroReach && $0.hand == "AA" && $0.spot == "LJ:r,BB:r|LJ" })
    }

    @Test func villainNeedsSomeHandThatTakesTheLine() throws {
        var book = try book()
        let open = try index(of: "|LJ", in: book)
        book.spots[open].grid = Array(repeating: String(repeating: "F", count: 13), count: 13)
        #expect(errors(book).contains { $0.rule == .villainReach && $0.spot == "LJ:r|HJ" })
    }

    @Test func mixedCellsAreSupportedAndChecked() throws {
        var book = try book()
        let open = try index(of: "|LJ", in: book)
        book.spots[open].grid[0] = String(book.spots[open].grid[0].dropLast()) + Spot.mixedCell

        book.spots[open].mix = ["A2s": ["R": 3_500, "F": 6_500]]
        #expect(errors(book).isEmpty)
        #expect(book.spots[open].frequency(of: .raise, for: "A2s") == 3_500)
        #expect(book.spots[open].primaryAction(for: "A2s") == .fold)

        book.spots[open].mix = ["A2s": ["R": 3_500, "F": 6_000]]
        #expect(errors(book).contains { $0.rule == .structure && $0.hand == "A2s" })

        book.spots[open].mix = nil
        #expect(errors(book).contains { $0.rule == .structure && $0.hand == "A2s" })
    }

    @Test func expectedSpotsCoverSixMax() {
        let expected = BookValidator.expectedSixMaxSpots()
        #expect(expected.count == 65)
        #expect(!expected.contains("|BB"))
        #expect(expected.allSatisfy { SpotKey(id: $0)?.isPlayable == true })
    }
}

struct ChartLibraryTests {
    @Test func bundledBookLoads() throws {
        let library = try ChartLibrary.bundled()
        #expect(library.book.schemaVersion == RangeBook.currentSchemaVersion)
        #expect(library.spot(id: "|LJ") != nil)
    }

    @Test func corruptDataThrowsInsteadOfCrashing() {
        #expect {
            try ChartLibrary.decode(Data("not json".utf8))
        } throws: { error in
            guard case ChartError.unreadable = error else { return false }
            return true
        }
    }

    @Test func newerFormatIsRefused() throws {
        var book = try ChartLibrary.bundled().book
        book.schemaVersion = 99
        #expect(throws: ChartError.unsupportedSchema(99)) {
            try ChartLibrary(book: book)
        }
    }

    @Test func repeatedSpotThrowsInsteadOfCrashing() throws {
        var book = try ChartLibrary.bundled().book
        book.spots.append(book.spots[0])
        #expect(throws: ChartError.duplicateSpot(book.spots[0].id)) {
            try ChartLibrary(book: book)
        }
    }

    @Test func reachFollowsTheHeroEarlierDecision() throws {
        let library = try ChartLibrary.bundled()
        let facing3Bet = try #require(SpotKey(id: "LJ:r,BB:r|LJ"))
        #expect(library.reach(of: "AA", in: facing3Bet) == .reached)
        #expect(library.reach(of: "72o", in: facing3Bet) == .notReached)

        let opening = try #require(SpotKey(id: "|LJ"))
        #expect(library.reach(of: "72o", in: opening) == .reached)

        let afterAColdCallNobodyMakes = try #require(SpotKey(id: "LJ:r,HJ:c,BB:r|HJ"))
        #expect(library.reach(of: "AA", in: afterAColdCallNobodyMakes) == .notReached)
    }

    @Test func reachIsUnknownWithoutAnEarlierSpot() throws {
        let library = try ChartLibrary.bundled()
        // CO's cold 4-bet isn't in this book, so we can't say which hands got here
        let afterColdFourBet = try #require(SpotKey(id: "LJ:r,HJ:r,CO:r,HJ:r|CO"))
        #expect(afterColdFourBet.isPlayable)
        #expect(library.reach(of: "AA", in: afterColdFourBet) == .unknown)
    }

    @Test func bookCountsEveryOpenReviewItem() throws {
        var book = try ChartLibrary.bundled().book
        #expect(book.openReviewCount == 0)

        book.patches[0].status = .inferred
        book.rules[0].status = .inferred
        book.disputes[0].status = .open
        #expect(book.openReviewCount == 3)
    }
}
