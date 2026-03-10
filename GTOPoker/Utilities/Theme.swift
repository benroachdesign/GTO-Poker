import SwiftUI

struct Theme {
    static let background = Color(hex: "1F2225") // Dark Grey Background
    static let gridEmpty = Color(hex: "292C31")
    
    static let raiseColor = Color(hex: "FF5E3A") // Orange
    static let callColor = Color(hex: "228B22") // Forest Green
    
    static let heroSeat = Color.white
    static let heroText = Color.black
    
    static let villainSeat = Color(hex: "FF5E3A")
    static let villainText = Color.white
    
    static let neutralSeat = Color.white.opacity(0.8)
    
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.5)
}

// Re-declaring Color(hex:) here if not already available globally, 
// or I can move the extension from PokerTable.swift to here.
// I'll create a shared Extension file or just put it here for cleanliness.

extension Color {
    init(hex: String, opacity: Double = 1.0) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: opacity
        )
    }
}
