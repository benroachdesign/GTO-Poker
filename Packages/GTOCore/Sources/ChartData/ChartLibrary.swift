import Foundation
import PokerDomain

public enum ChartError: Error, Equatable, CustomStringConvertible {
    case missingResource(String)
    case unreadable(String)
    case unsupportedSchema(Int)
    case duplicateSpot(String)

    public var description: String {
        switch self {
        case .missingResource(let name): return "\(name) is missing from the app."
        case .unreadable(let detail): return "The range data could not be read: \(detail)"
        case .unsupportedSchema(let version): return "The range data uses unsupported format version \(version)."
        case .duplicateSpot(let id): return "The range data lists spot \(id) twice."
        }
    }
}

public enum HandReach: Sendable {
    case reached
    case notReached // The hero already folded this hand
    case unknown    // The hero's earlier decision isn't in this book
}

/// A loaded book, indexed for lookup. Loading throws rather than crashing on bad data.
public struct ChartLibrary: Sendable {
    public static let bundledBookName = "6max-100"

    public let book: RangeBook
    private let spotsByID: [String: Spot]

    public init(book: RangeBook) throws {
        guard book.schemaVersion == RangeBook.currentSchemaVersion else {
            throw ChartError.unsupportedSchema(book.schemaVersion)
        }

        var spotsByID: [String: Spot] = [:]
        for spot in book.spots {
            guard spotsByID[spot.id] == nil else { throw ChartError.duplicateSpot(spot.id) }
            spotsByID[spot.id] = spot
        }
        self.book = book
        self.spotsByID = spotsByID
    }

    public static func decode(_ data: Data) throws -> ChartLibrary {
        let book: RangeBook
        do {
            book = try JSONDecoder().decode(RangeBook.self, from: data)
        } catch {
            throw ChartError.unreadable(String(describing: error))
        }
        return try ChartLibrary(book: book)
    }

    /// The only place that touches `Bundle.module`, because it traps if the bundle is missing.
    public static func bundled() throws -> ChartLibrary {
        guard let url = Bundle.module.url(forResource: bundledBookName, withExtension: "json") else {
            throw ChartError.missingResource("\(bundledBookName).json")
        }
        do {
            return try decode(Data(contentsOf: url))
        } catch let error as ChartError {
            throw error
        } catch {
            throw ChartError.unreadable(String(describing: error))
        }
    }

    public func spot(id: String) -> Spot? {
        spotsByID[id]
    }

    public func spot(_ key: SpotKey) -> Spot? {
        spotsByID[key.id]
    }

    public func reach(of hand: String, in key: SpotKey) -> HandReach {
        ChartLibrary.reach(of: hand, in: key, spots: spotsByID)
    }

    static func reach(of hand: String, in key: SpotKey, spots: [String: Spot]) -> HandReach {
        guard let previous = key.heroPreviousDecision else { return .reached }
        guard let parent = spots[previous.spot.id] else { return .unknown }
        return parent.frequency(of: OptionKind(previous.kind), for: hand) > 0 ? .reached : .notReached
    }
}
