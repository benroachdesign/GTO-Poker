import SwiftUI
import ChartData

enum Theme {
    static let background = Color(hex: "16181B")
    static let surface = Color.white.opacity(0.05)
    static let surfaceRaised = Color.white.opacity(0.1)
    static let hairline = Color.white.opacity(0.1)
    static let felt = Color(hex: "1C3026")

    static let raise = Color(hex: "FF5E3A")
    static let allIn = Color(hex: "C4183C")
    static let call = Color(hex: "228B22")
    static let fold = Color(hex: "2A2D32")
    static let correct = Color(hex: "4CC26A") // Brighter than call, so a verdict reads on dark text

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.6)
    static let textTertiary = Color.white.opacity(0.35)

    /// Critically damped: settles without overshoot and can be interrupted at any point.
    static let motion = Animation.spring(response: 0.38, dampingFraction: 1)
    static let press = Animation.spring(response: 0.2, dampingFraction: 1)

    static func color(for action: OptionKind) -> Color {
        switch action {
        case .raise: return raise
        case .allIn: return allIn
        case .call: return call
        case .fold: return fold
        }
    }
}

enum BetText {
    static func size(_ bigBlinds: Double) -> String {
        "\(bigBlinds.formatted(.number.precision(.fractionLength(0...1))))bb"
    }

    static func share(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(1)))
    }
}

/// Responds on touch-down, so every control feels direct.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

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
