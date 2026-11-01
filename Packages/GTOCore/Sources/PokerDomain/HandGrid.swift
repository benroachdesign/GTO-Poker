import Foundation

/// The standard 13x13 starting-hand grid: pairs on the diagonal,
/// suited hands above it, offsuit hands below it.
public enum HandGrid {
    // Ranks for 13x13 grid
    public static let ranks = ["A", "K", "Q", "J", "T", "9", "8", "7", "6", "5", "4", "3", "2"]

    public static func getHandName(row: Int, col: Int) -> String {
        let r1 = ranks[row]
        let r2 = ranks[col]
        if row == col { return "\(r1)\(r2)" }
        if row < col { return "\(r1)\(r2)s" }
        return "\(r2)\(r1)o"
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
