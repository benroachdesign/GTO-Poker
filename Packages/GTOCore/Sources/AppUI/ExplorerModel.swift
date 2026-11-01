import Foundation
import Observation
import ChartData
import PokerDomain

/// Where the explorer is, and everything shown about that spot.
/// It only ever moves to spots the book contains, so dead ends can't be reached.
@MainActor
@Observable
final class ExplorerModel {
    let library: ChartLibrary

    private(set) var key: SpotKey
    private(set) var cells: [String: CellState] = [:]
    private(set) var choices: [SpotChoice] = []
    private(set) var entries: [LineEntry] = []
    private(set) var table: TableState
    private(set) var reachedShare = 1.0
    var selectedHand: String?

    init?(library: ChartLibrary, startingAt id: String? = nil) {
        guard let key = id.flatMap(SpotKey.init(id:)).flatMap({ library.spot($0) == nil ? nil : $0 }) ?? library.firstSpot else {
            return nil
        }
        self.library = library
        self.key = key
        table = library.tableState(at: key)
        refresh()
    }

    func go(to destination: SpotKey) {
        guard library.spot(destination) != nil else { return }
        key = destination
        refresh()
    }

    func choose(_ choice: SpotChoice) {
        if let destination = choice.destination { go(to: destination) }
    }

    /// Chooses by option code, for the keyboard: R, A, C or F. Returns whether it moved.
    @discardableResult
    func choose(code: String) -> Bool {
        guard let choice = choices.first(where: { $0.code == code.uppercased() }), choice.destination != nil else {
            return false
        }
        choose(choice)
        return true
    }

    func canTap(_ seat: Position) -> Bool {
        library.destination(tapping: seat, from: key) != nil
    }

    func tap(_ seat: Position) {
        if let destination = library.destination(tapping: seat, from: key) { go(to: destination) }
    }

    /// Moves to the next seat on this line, or the next opponent when only one seat can act.
    func cycle(by offset: Int) {
        if let neighbour = library.neighbour(of: key, by: offset) {
            go(to: neighbour)
            return
        }
        let opponents = library.opponents(of: key)
        guard let index = opponents.firstIndex(of: key) else { return }
        go(to: opponents[(index + offset + opponents.count) % opponents.count])
    }

    func goBack() {
        if let previous = entries.last { go(to: previous.spot) }
    }

    var journey: [HandStep] {
        selectedHand.map { library.journey(of: $0, to: key) } ?? []
    }

    var comparison: HandComparison? {
        selectedHand.map { library.comparison(of: $0, at: key) }
    }

    private func refresh() {
        table = library.tableState(at: key)
        choices = library.choices(at: key)
        entries = library.lineEntries(to: key)
        reachedShare = library.reachedShare(at: key)

        guard let spot = library.spot(key) else { return }
        var cells: [String: CellState] = [:]
        for hand in HandGrid.allHands {
            cells[hand] = library.reach(of: hand, in: key) == .notReached ? .unreached : .action(spot.primaryAction(for: hand))
        }
        self.cells = cells
    }
}
