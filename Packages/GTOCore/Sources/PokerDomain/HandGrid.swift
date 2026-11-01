import Foundation

/// The standard 13x13 starting-hand grid: pairs on the diagonal,
/// suited hands above it, offsuit hands below it.
public enum HandGrid {
    // Ranks for 13x13 grid
    public static let ranks = ["A", "K", "Q", "J", "T", "9", "8", "7", "6", "5", "4", "3", "2"]

    public static let allHands: [String] = (0..<13).flatMap { row in
        (0..<13).map { col in getHandName(row: row, col: col) }
    }

    public static func getHandName(row: Int, col: Int) -> String {
        let r1 = ranks[row]
        let r2 = ranks[col]
        if row == col { return "\(r1)\(r2)" }
        if row < col { return "\(r1)\(r2)s" }
        return "\(r2)\(r1)o"
    }

    /// Where a hand sits on the grid. Inverse of `getHandName`.
    public static func coordinates(of hand: String) -> (row: Int, col: Int)? {
        let letters = hand.map(String.init)
        guard letters.count == 2 || letters.count == 3,
              let first = ranks.firstIndex(of: letters[0]),
              let second = ranks.firstIndex(of: letters[1]) else { return nil }

        if letters.count == 2 { return first == second ? (first, first) : nil }
        guard first != second else { return nil }
        switch letters[2] {
        case "s": return (first, second)
        case "o": return (second, first)
        default: return nil
        }
    }

    public static func getCombos(for hand: String) -> Double {
        // Pairs: 6 combos (AA, KK...)
        if hand.count == 2 && hand.first == hand.last { return 6.0 }
        // Suited: 4 combos (AKs...)
        if hand.hasSuffix("s") { return 4.0 }
        // Offsuit: 12 combos (AKo...)
        if hand.hasSuffix("o") { return 12.0 }
        return 0.0
    }
}
