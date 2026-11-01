import Testing
import ChartData
import PokerDomain
@testable import AppUI

@MainActor
struct ExplorerModelTests {
    private let library: ChartLibrary

    init() throws {
        library = try ChartLibrary.bundled()
    }

    private func model(at id: String? = nil) throws -> ExplorerModel {
        try #require(ExplorerModel(library: library, startingAt: id))
    }

    private func choice(_ model: ExplorerModel, _ kind: OptionKind) throws -> SpotChoice {
        try #require(model.choices.first { $0.kind == kind })
    }

    @Test func startsAtTheFirstSeat() throws {
        #expect(try model().key.id == "|LJ")
    }

    @Test func returnsToTheLastSpot() throws {
        #expect(try model(at: "LJ:r,BTN:r|LJ").key.id == "LJ:r,BTN:r|LJ")
    }

    @Test(arguments: ["|BB", "nonsense", ""])
    func ignoresASavedSpotThatDoesntExist(saved: String) throws {
        #expect(try model(at: saved).key.id == "|LJ")
    }

    @Test func walkingAHandFollowsTheAction() throws {
        let model = try model()

        model.choose(try choice(model, .raise))
        #expect(model.key.id == "LJ:r|HJ")

        model.tap(.BTN)
        #expect(model.key.id == "LJ:r|BTN")

        model.choose(try choice(model, .raise))
        #expect(model.key.id == "LJ:r,BTN:r|LJ")
        #expect(model.table.hero == .LJ)
        #expect(model.entries.map(\.title) == ["Open", "3-Bet"])
    }

    @Test func choosingAnOptionWithNowhereToGoStaysPut() throws {
        let model = try model(at: "LJ:r|BB")
        model.choose(try choice(model, .call))
        #expect(model.key.id == "LJ:r|BB")
    }

    @Test func everyChoiceHasItsOwnKey() throws {
        let model = try model(at: "LJ:r|BB")
        #expect(model.choices.compactMap { $0.shortcut?.key.character } == ["r", "c", "f"])
    }

    @Test func goingBackStepsAlongTheLine() throws {
        let model = try model(at: "LJ:r,BTN:r|LJ")
        model.goBack()
        #expect(model.key.id == "LJ:r|BTN")
        model.goBack()
        #expect(model.key.id == "|LJ")
        model.goBack()
        #expect(model.key.id == "|LJ")
    }

    @Test func cyclingMovesAroundSeats() throws {
        let model = try model(at: "|LJ")
        model.cycle(by: -1)
        #expect(model.key.id == "|SB")
        model.cycle(by: 1)
        #expect(model.key.id == "|LJ")
    }

    @Test func cyclingMovesAroundOpponentsWhenOnlyOneSeatActs() throws {
        let model = try model(at: "LJ:r,BTN:r|LJ")
        model.cycle(by: 1)
        #expect(model.key.id == "LJ:r,SB:r|LJ")
        model.cycle(by: -1)
        #expect(model.key.id == "LJ:r,BTN:r|LJ")
    }

    @Test func handsAlreadyFoldedAreMarkedOnTheGrid() throws {
        let model = try model(at: "LJ:r,BTN:r|LJ")
        #expect(model.cells["72o"] == .unreached)
        #expect(model.cells["AA"] == .action(.raise))
        #expect(model.cells.count == 169)
    }

    @Test func foldedHandsStayDistinctFromHandsThatNeverArrived() throws {
        let model = try model(at: "LJ:r,BTN:r|LJ")
        let opened = library.spot(id: "|LJ")
        let foldsToThe3Bet = HandGrid.allHands.first {
            opened?.primaryAction(for: $0) == .raise && model.cells[$0] == .action(.fold)
        }
        #expect(foldsToThe3Bet != nil)
    }

    @Test func selectionFollowsTheHandAcrossSpots() throws {
        let model = try model()
        model.selectedHand = "AJs"
        model.choose(try choice(model, .raise))
        #expect(model.selectedHand == "AJs")
        #expect(model.journey.isEmpty == false)
        #expect(model.comparison != nil)
    }
}
