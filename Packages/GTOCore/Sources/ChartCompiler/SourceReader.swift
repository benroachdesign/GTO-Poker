import Foundation
import ChartData

/// A scenario label as the source sheet writes it, e.g. vs 4bet / BB / HJ.
public struct SpotLabel: Codable, Hashable, Sendable, CustomStringConvertible {
    public var scenario: String
    public var hero: String
    public var villain: String

    public init(scenario: String, hero: String, villain: String) {
        self.scenario = scenario
        self.hero = hero
        self.villain = villain
    }

    public var description: String {
        villain.isEmpty ? "\(scenario) \(hero)" : "\(scenario) \(hero) v \(villain)"
    }
}

/// One 13x13 chart from the source CSV.
public struct SourceBlock: Sendable {
    public var label: SpotLabel
    public let sourceLine: Int // Line of the chart's first row, counting from 1
    public let players: Int
    public let stack: Int
    public let grid: [String]
}

public enum CompileError: Error, Equatable, CustomStringConvertible {
    case malformedBlock(line: Int)
    case unknownCell(line: Int, value: String)
    case unknownLabel(line: Int, label: String)
    case duplicateLabels([String])
    case sourceChanged(expected: String, actual: String)
    case stalePatch(id: String, detail: String)
    case unknownDisputeSpot(dispute: String, spot: String)
    case bookMismatch(line: Int, detail: String)

    public var description: String {
        switch self {
        case .malformedBlock(let line): return "Chart at line \(line) is malformed"
        case .unknownCell(let line, let value): return "Line \(line) has unknown cell value \"\(value)\""
        case .unknownLabel(let line, let label): return "Line \(line) has unknown label \"\(label)\""
        case .duplicateLabels(let labels): return "Several charts share a label: \(labels.joined(separator: "; "))"
        case .sourceChanged(let expected, let actual): return "Source CSV changed. Expected \(expected), found \(actual)"
        case .stalePatch(let id, let detail): return "Patch \(id) no longer applies: \(detail)"
        case .unknownDisputeSpot(let dispute, let spot): return "Dispute \(dispute) names unknown spot \(spot)"
        case .bookMismatch(let line, let detail): return "Line \(line): \(detail)"
        }
    }
}

public enum SourceReader {
    private static let firstGridColumn = 6
    private static let blockHeight = 14 // A header row, then 13 grid rows

    public static func parse(csv: String) throws -> [SourceBlock] {
        let rows = csv
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }

        var blocks: [SourceBlock] = []
        var index = 0

        while index < rows.count {
            guard rows[index].first == "Players" else {
                index += 1
                continue
            }

            let firstRow = index + 1
            let sourceLine = firstRow + 1
            guard firstRow + 13 <= rows.count, rows[firstRow].count >= firstGridColumn + 13,
                  let players = Int(rows[firstRow][0]), let stack = Int(rows[firstRow][1]) else {
                throw CompileError.malformedBlock(line: sourceLine)
            }

            var grid: [String] = []
            for row in 0..<13 {
                let cells = rows[firstRow + row]
                guard cells.count >= firstGridColumn + 13 else {
                    throw CompileError.malformedBlock(line: sourceLine + row)
                }
                grid.append(try cells[firstGridColumn..<(firstGridColumn + 13)].map { cell in
                    try optionCode(cell, line: sourceLine + row)
                }.joined())
            }

            let meta = rows[firstRow]
            blocks.append(SourceBlock(
                label: SpotLabel(scenario: meta[2], hero: meta[3], villain: meta[4]),
                sourceLine: sourceLine,
                players: players,
                stack: stack,
                grid: grid
            ))
            index += blockHeight
        }
        return blocks
    }

    private static func optionCode(_ cell: String, line: Int) throws -> String {
        let value = cell.trimmingCharacters(in: .whitespaces).uppercased()
        if value.isEmpty { return OptionKind.fold.code }
        guard OptionKind(code: value) != nil else {
            throw CompileError.unknownCell(line: line, value: cell)
        }
        return value
    }
}
