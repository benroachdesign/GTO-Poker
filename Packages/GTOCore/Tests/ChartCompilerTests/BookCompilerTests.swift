import Foundation
import Testing
import ChartData
import PokerDomain
@testable import ChartCompiler

/// These run against the real Data folder, so they guard the actual repairs.
struct BookCompilerTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // ChartCompilerTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // GTOCore
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent()
    private static let dataFolder = root.appendingPathComponent("Data")
    private static let bookFile = root.appendingPathComponent("Packages/GTOCore/Sources/ChartData/Resources/6max-100.json")

    private func patches() throws -> PatchFile {
        try JSONDecoder().decode(PatchFile.self, from: Data(contentsOf: Self.dataFolder.appendingPathComponent(BookCompiler.patchFileName)))
    }

    private func csv() throws -> Data {
        try Data(contentsOf: Self.dataFolder.appendingPathComponent(patches().source.file))
    }

    private func legacy() throws -> RangeBook {
        try BookCompiler.importLegacy(
            Data(contentsOf: Self.dataFolder.appendingPathComponent(BookCompiler.legacyFileName)),
            rules: patches().actionRules
        )
    }

    private func compiled() throws -> RangeBook {
        try BookCompiler.compile(csv: csv(), patches: patches(), legacy: legacy())
    }

    @Test func sourceCSVMatchesItsRecordedHash() throws {
        #expect(try BookCompiler.sha256(csv()) == patches().source.sha256)
    }

    @Test func compiledBookPassesEveryRule() throws {
        let book = try compiled()
        #expect(book.spots.count == 65)
        #expect(BookValidator.validate(book).filter { $0.severity == .error }.isEmpty)
    }

    @Test func bundledBookIsUpToDateAndByteIdentical() throws {
        let first = try BookCompiler.encode(compiled())
        let second = try BookCompiler.encode(compiled())
        #expect(first == second)
        #expect(try first == Data(contentsOf: Self.bookFile))
    }

    @Test func legacyDataFailsWithExactlyEightUnreachableHands() throws {
        let errors = try BookValidator.validate(legacy()).filter { $0.severity == .error }
        #expect(errors.count == 8)
        #expect(errors.allSatisfy { $0.rule == .heroReach })

        let bySpot = Dictionary(grouping: errors) { $0.spot ?? "" }.mapValues(\.count)
        #expect(bySpot == ["BTN:r,BB:r,BTN:r|BB": 1, "CO:r,BB:r,CO:r|BB": 4, "SB:r,BB:r,SB:r|BB": 3])
    }

    @Test func repairChangesExactlyTheAgreedSeventeenCells() throws {
        let book = try compiled()
        let before = Dictionary(uniqueKeysWithValues: try legacy().spots.map { ($0.id, $0) })

        var changedCells: [String: Int] = [:]
        for spot in book.spots {
            let old = try #require(before[spot.id])
            let count = HandGrid.allHands.filter { old.code(for: $0) != spot.code(for: $0) }.count
            if count > 0 { changedCells[spot.id] = count }
        }
        #expect(changedCells == ["CO:r,BB:r,CO:r|BB": 5, "BTN:r,BB:r,BTN:r|BB": 4, "SB:r,BB:r,SB:r|BB": 8])

        let recorded = Dictionary(uniqueKeysWithValues: book.patches.map { ($0.spot, $0.changes.count) })
        #expect(recorded == changedCells)
    }

    @Test func onlyPatchedChartsMoveAwayFromTheirSourceLabel() throws {
        let book = try compiled()
        let blocks = try SourceReader.parse(csv: String(decoding: csv(), as: UTF8.self))
        let byLine = Dictionary(uniqueKeysWithValues: blocks.map { ($0.sourceLine, $0) })

        for spot in book.spots {
            let block = try #require(byLine[spot.provenance.sourceLine ?? 0])
            let expected = block.label.scenario == "vs 4bet" ? block.grid.map { $0.replacingOccurrences(of: "R", with: "A") } : block.grid
            #expect(expected == spot.grid, "\(spot.id)")

            let scenario = try #require(ScenarioType(rawValue: block.label.scenario))
            let hero = try #require(Position(rawValue: block.label.hero))
            let key = SpotKey(scenario: scenario, hero: hero, villain: Position(rawValue: block.label.villain))
            #expect((key?.id == spot.id) == (spot.provenance.patches == nil), "\(spot.id)")
        }
    }

    @Test func reviewCanRebuildTheRangeFromBeforeARepair() throws {
        let book = try compiled()
        let before = Dictionary(uniqueKeysWithValues: try legacy().spots.map { ($0.id, $0) })
        let spots = Dictionary(uniqueKeysWithValues: book.spots.map { ($0.id, $0) })

        for patch in book.patches {
            let spot = try #require(spots[patch.spot])
            let old = try #require(before[patch.spot])
            #expect(PokerRange(spot: spot).reverting(patch.changes).ranges == PokerRange(spot: old).ranges)
        }
    }

    @Test func everyRulingIsRecorded() throws {
        let book = try compiled()
        #expect(book.openReviewCount == 0)
        #expect(book.patches.allSatisfy { $0.status == .confirmed && $0.decidedBy != nil })
        #expect(book.rules.allSatisfy { $0.status == .confirmed && $0.decidedBy != nil })
        #expect(book.disputes.allSatisfy { $0.status == .resolved && $0.ruling != nil && $0.decidedBy != nil })
    }

    @Test func rulingsToKeepAChartLeaveItUnchanged() throws {
        let spots = Dictionary(uniqueKeysWithValues: try compiled().spots.map { ($0.id, $0) })

        #expect(spots["|SB"]?.grid == spots["|BTN"]?.grid)
        #expect(spots["|SB"]?.provenance.status == .source)
        #expect(spots["CO:r,BTN:r,CO:r|BTN"]?.code(for: "AA") == "C")
        #expect(spots["SB:r,BB:r,SB:r|BB"]?.code(for: "AA") == "C")
        #expect(spots["CO:r,BB:r,CO:r|BB"]?.provenance.status == .confirmed)
    }

    @Test func raisesFacingA4BetBecomeAllIns() throws {
        let book = try compiled()
        let cells = { (scenario: Int, code: Character) in
            book.spots
                .filter { $0.key?.line.count == scenario }
                .reduce(0) { $0 + $1.grid.joined().filter { $0 == code }.count }
        }
        #expect(cells(3, "A") == 89)
        #expect(cells(3, "R") == 0)
        #expect(cells(4, "R") == 0)
        #expect(book.spots.filter { $0.key?.line.count != 3 }.allSatisfy { !$0.grid.joined().contains("A") })
    }

    @Test func fiveBetLinesEndInAnAllIn() throws {
        let spots = try compiled().spots.filter { $0.key?.line.count == 4 }
        #expect(spots.count == 15)
        #expect(spots.allSatisfy { $0.key?.line.last?.kind == .allIn })
    }

    @Test func spotsOnlyOfferActionsTheyUse() throws {
        let spots = Dictionary(uniqueKeysWithValues: try compiled().spots.map { ($0.id, $0) })
        #expect(spots["|LJ"]?.options.map(\.kind) == [.raise, .fold])
        #expect(spots["LJ:r,BTN:r,LJ:r|BTN"]?.options.map(\.kind) == [.allIn, .call, .fold])
        #expect(spots["LJ:r,BTN:r,LJ:r,BTN:a|LJ"]?.options.map(\.kind) == [.call, .fold])
    }

    @Test func raisesCarryTheRuledSizes() throws {
        let spots = Dictionary(uniqueKeysWithValues: try compiled().spots.map { ($0.id, $0) })
        let size = { (id: String, kind: OptionKind) in
            spots[id]?.options.first { $0.kind == kind }?.sizeBB
        }

        #expect(size("|LJ", .raise) == 3.5)
        #expect(size("|BTN", .raise) == 2.5)
        #expect(size("|SB", .raise) == 3.5)

        #expect(size("LJ:r|BTN", .raise) == 10.5)   // 3.5 x 3, in position
        #expect(size("BTN:r|BB", .raise) == 8.75)   // 2.5 x 3.5, out of position
        #expect(size("SB:r|BB", .raise) == 10.5)    // 3.5 x 3, the BB has position on the SB

        #expect(size("LJ:r,BTN:r|LJ", .raise) == 28.88)  // 10.5 x 2.75, out of position
        #expect(size("BTN:r,BB:r|BTN", .raise) == 21.88) // 8.75 x 2.5, in position
        #expect(size("CO:r,BTN:r|CO", .raise) == 20.63)  // 7.5 x 2.75, the BTN has position on the CO

        #expect(size("LJ:r,BTN:r,LJ:r|BTN", .allIn) == 100)
        #expect(size("|LJ", .fold) == nil)
    }

    @Test func identicalRangesAreReportedAsWarnings() throws {
        let identical = BookValidator.validate(try compiled()).filter { $0.rule == .identicalRanges }
        #expect(identical.allSatisfy { $0.severity == .warning })
        #expect(identical.count == 6)
    }

    @Test func unpatchedSourceIsRejectedForItsDuplicateLabels() throws {
        var file = try patches()
        file.patches = []
        #expect {
            try BookCompiler.compile(csv: csv(), patches: file, legacy: nil)
        } throws: { error in
            guard case CompileError.duplicateLabels(let labels) = error else { return false }
            return labels == ["vs 4bet BB v HJ at lines 646, 660, 674, 688"]
        }
    }

    @Test func patchThatNoLongerMatchesIsRejected() throws {
        var file = try patches()
        file.patches[0].from.villain = "LJ"
        #expect(throws: CompileError.self) {
            try BookCompiler.compile(csv: csv(), patches: file, legacy: nil)
        }
    }

    @Test func changedSourceIsRejected() throws {
        var changed = try csv()
        changed.append(contentsOf: Data("\n".utf8))
        #expect(throws: CompileError.self) {
            try BookCompiler.compile(csv: changed, patches: patches(), legacy: nil)
        }
    }

    @Test func unknownCellValueIsRejectedRatherThanTreatedAsFold() {
        let row = ",,,,,Ao,X,F,F,F,F,F,F,F,F,F,F,F,F,,"
        let header = "Players,Stacks,Scenario,Hero,Villain,,As,Ks,Qs,Js,Ts,9s,8s,7s,6s,5s,4s,3s,2s,,"
        let meta = "6,100,Open,LJ,,Ao,X,F,F,F,F,F,F,F,F,F,F,F,F,,"
        let csv = ([header, meta] + Array(repeating: row, count: 12)).joined(separator: "\r\n")
        #expect(throws: CompileError.unknownCell(line: 2, value: "X")) {
            try SourceReader.parse(csv: csv)
        }
    }
}
