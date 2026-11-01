import Foundation
import CryptoKit
import ChartData
import PokerDomain

/// `Data/patches.json`: everything about a book that isn't in the source CSV.
public struct PatchFile: Codable, Sendable {
    public struct BookDefinition: Codable, Sendable {
        public var id: String
        public var title: String
        public var format: String
        public var players: Int
        public var stackBB: Int
    }

    public struct Definition: Codable, Sendable {
        public var id: String
        public var kind: String
        public var sourceLine: Int
        public var from: SpotLabel
        public var to: SpotLabel
        public var reason: String
        public var evidence: String
        public var decidedBy: String?
        public var status: PatchStatus
    }

    public var schemaVersion: Int
    public var book: BookDefinition
    public var source: SourceInfo
    public var patches: [Definition]
    public var actionRules: [ActionRule]
    public var sizing: SizingRules?
    public var disputes: [Dispute]
}

/// The sizes a raise goes to, by seat for opens and by position after that.
public struct SizingRules: Codable, Sendable {
    public struct Multiples: Codable, Sendable {
        public var inPosition: Double
        public var outOfPosition: Double
    }

    public var opens: [String: Double]
    public var threeBet: Multiples
    public var fourBet: Multiples

    /// What the hero raises to at this spot, in big blinds. Nil past a 4-bet,
    /// where these charts only go all-in.
    func raiseSize(at key: SpotKey) -> Double? {
        var size: Double?
        var lastRaiser: Position?
        let raisers = key.line.filter { $0.kind == .raise }.map(\.position) + [key.hero]

        for (level, raiser) in raisers.enumerated() {
            switch level {
            case 0:
                size = opens[raiser.rawValue]
            case 1, 2:
                guard let previous = size, let opponent = lastRaiser else { return nil }
                let multiples = level == 1 ? threeBet : fourBet
                size = previous * (raiser.isInPosition(against: opponent) ? multiples.inPosition : multiples.outOfPosition)
            default:
                return nil
            }
            lastRaiser = raiser
        }
        return size.map { ($0 * 100).rounded() / 100 }
    }
}

public enum BookCompiler {
    public static let legacyFileName = "legacy_poker_ranges.json"
    public static let patchFileName = "patches.json"

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Turns the untouched source CSV plus its patches into a book.
    /// `legacy` is the range data the app shipped before, used to record what each repair changes.
    public static func compile(csv: Data, patches file: PatchFile, legacy: RangeBook?) throws -> RangeBook {
        let actualHash = sha256(csv)
        guard actualHash == file.source.sha256 else {
            throw CompileError.sourceChanged(expected: file.source.sha256, actual: actualHash)
        }

        var blocks = try SourceReader.parse(csv: String(decoding: csv, as: UTF8.self))
        var patchByLine: [Int: PatchFile.Definition] = [:]

        for patch in file.patches {
            guard let index = blocks.firstIndex(where: { $0.sourceLine == patch.sourceLine }) else {
                throw CompileError.stalePatch(id: patch.id, detail: "no chart at line \(patch.sourceLine)")
            }
            guard blocks[index].label == patch.from else {
                throw CompileError.stalePatch(id: patch.id, detail: "line \(patch.sourceLine) is labelled \(blocks[index].label), not \(patch.from)")
            }
            blocks[index].label = patch.to
            patchByLine[patch.sourceLine] = patch
        }

        let repeated = Dictionary(grouping: blocks, by: \.label).filter { $0.value.count > 1 }
        guard repeated.isEmpty else {
            throw CompileError.duplicateLabels(repeated.map { label, group in
                "\(label) at lines \(group.map { String($0.sourceLine) }.joined(separator: ", "))"
            }.sorted())
        }

        var spots: [Spot] = []
        var compiledPatches: [Patch] = []
        let legacyByID = Dictionary(uniqueKeysWithValues: (legacy?.spots ?? []).map { ($0.id, $0) })

        for block in blocks {
            guard block.players == file.book.players, block.stack == file.book.stackBB else {
                throw CompileError.bookMismatch(line: block.sourceLine, detail: "chart is \(block.players) players at \(block.stack)bb")
            }

            let key = try spotKey(for: block)
            let rules = file.actionRules.filter { $0.scenario == block.label.scenario }
            let grid = applying(rules, to: block.grid)
            let patch = patchByLine[block.sourceLine]
            let disputes = file.disputes.filter { $0.status == .open && $0.spots.contains(key.id) }.map(\.id)

            let spot = Spot(
                id: key.id,
                options: options(in: grid, at: key, stack: file.book.stackBB, sizing: file.sizing),
                grid: grid,
                provenance: Provenance(
                    sourceLine: block.sourceLine,
                    status: status(patch: patch, rules: rules, disputes: disputes),
                    patches: patch.map { [$0.id] },
                    rules: rules.isEmpty ? nil : rules.map(\.id),
                    disputes: disputes.isEmpty ? nil : disputes
                )
            )
            spots.append(spot)

            if let patch {
                compiledPatches.append(Patch(
                    id: patch.id,
                    kind: patch.kind,
                    spot: key.id,
                    sourceLine: patch.sourceLine,
                    originalLabel: patch.from.description,
                    reason: patch.reason,
                    evidence: patch.evidence,
                    decidedBy: patch.decidedBy,
                    status: patch.status,
                    changes: legacyByID[key.id].map { changes(from: $0, to: spot) } ?? []
                ))
            }
        }

        let ids = Set(spots.map(\.id))
        for dispute in file.disputes {
            for spot in dispute.spots where !ids.contains(spot) {
                throw CompileError.unknownDisputeSpot(dispute: dispute.id, spot: spot)
            }
        }

        return RangeBook(
            book: BookInfo(id: file.book.id, title: file.book.title, format: file.book.format, stackBB: file.book.stackBB, source: file.source),
            spots: spots,
            patches: compiledPatches.sorted { $0.id < $1.id },
            rules: file.actionRules,
            disputes: file.disputes
        )
    }

    /// Stable output, so regenerating an unchanged book is byte-identical
    /// and a data repair shows up as a small diff.
    public static func encode(_ book: RangeBook) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(book) + Data("\n".utf8)
    }

    /// Reads the flat range file the app shipped before version 2. Action rules
    /// are applied so comparisons show only real repairs, not relabelled cells.
    public static func importLegacy(_ data: Data, rules: [ActionRule] = []) throws -> RangeBook {
        struct LegacyRange: Decodable {
            let scenario: String
            let hero: String
            let villain: String?
            let ranges: [String: String]
        }

        let source = SourceInfo(file: legacyFileName, sha256: sha256(data))
        let spots = try JSONDecoder().decode([LegacyRange].self, from: data).map { range in
            let label = SpotLabel(scenario: range.scenario, hero: range.hero, villain: range.villain ?? "")
            let key = try spotKey(label: label, line: 0)
            let grid = applying(rules.filter { $0.scenario == range.scenario }, to: (0..<13).map { row in
                (0..<13).map { col -> String in
                    let action = range.ranges[HandGrid.getHandName(row: row, col: col)]
                    return OptionKind.allCases.first { $0.label == action }?.code ?? OptionKind.fold.code
                }.joined()
            })
            return Spot(
                id: key.id,
                options: options(in: grid, at: key, stack: 100, sizing: nil),
                grid: grid,
                provenance: Provenance(sourceLine: nil, status: .source)
            )
        }
        return RangeBook(
            book: BookInfo(id: "legacy", title: "Legacy ranges", format: "6max", stackBB: 100, source: source),
            spots: spots
        )
    }

    private static func spotKey(for block: SourceBlock) throws -> SpotKey {
        try spotKey(label: block.label, line: block.sourceLine)
    }

    private static func spotKey(label: SpotLabel, line: Int) throws -> SpotKey {
        guard let scenario = ScenarioType(rawValue: label.scenario),
              let hero = Position(rawValue: label.hero) else {
            throw CompileError.unknownLabel(line: line, label: label.description)
        }
        let villain = label.villain.isEmpty ? nil : Position(rawValue: label.villain)
        guard label.villain.isEmpty || villain != nil,
              let key = SpotKey(scenario: scenario, hero: hero, villain: villain) else {
            throw CompileError.unknownLabel(line: line, label: label.description)
        }
        return key
    }

    private static func applying(_ rules: [ActionRule], to grid: [String]) -> [String] {
        rules.reduce(grid) { grid, rule in
            grid.map { $0.replacingOccurrences(of: rule.from, with: rule.to) }
        }
    }

    /// Only the actions a spot really uses, plus fold.
    private static func options(in grid: [String], at key: SpotKey, stack: Int, sizing: SizingRules?) -> [SpotOption] {
        let present = Set(grid.joined().map(String.init))
        return OptionKind.allCases
            .filter { $0 == .fold || present.contains($0.code) }
            .map { kind in
                switch kind {
                case .raise: return SpotOption(code: kind.code, kind: kind, sizeBB: sizing?.raiseSize(at: key))
                case .allIn: return SpotOption(code: kind.code, kind: kind, sizeBB: Double(stack))
                case .call, .fold: return SpotOption(code: kind.code, kind: kind)
                }
            }
    }

    private static func status(patch: PatchFile.Definition?, rules: [ActionRule], disputes: [String]) -> SpotStatus {
        if !disputes.isEmpty { return .disputed }
        if patch?.status == .inferred || rules.contains(where: { $0.status == .inferred }) { return .inferred }
        return patch == nil && rules.isEmpty ? .source : .confirmed
    }

    private static func changes(from old: Spot, to new: Spot) -> [CellChange] {
        HandGrid.allHands.compactMap { hand in
            guard let was = old.code(for: hand), let now = new.code(for: hand), was != now else { return nil }
            return CellChange(hand: hand, was: was, now: now)
        }
    }
}
